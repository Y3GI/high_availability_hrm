import functions_framework
import os
import json
import base64
import secrets
import string
from github import Github, InputGitTreeElement  # PyGithub
from google.cloud import secretmanager


def get_github_token() -> str:
    """Read GitHub PAT from Secret Manager."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{os.environ['GOOGLE_CLOUD_PROJECT']}/secrets/{os.environ.get('GITHUB_TOKEN_SECRET_ID', 'dev-github-token')}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")


def generate_password(length: int = 24) -> str:
    """Generate a secure random password for the workspace."""
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def build_workspace_manifest(employee_id: str, department: str, project: str, env: str) -> str:
    """Render workspace.yaml.tpl with employee values."""
    template_path = "workspace.yaml.tpl"
    with open(template_path) as f:
        template = f.read()

    return template \
        .replace("${EMPLOYEE_ID}", employee_id) \
        .replace("${DEPARTMENT}", department) \
        .replace("${GOOGLE_CLOUD_PROJECT}", project) \
        .replace("${ENV}", env)


def build_secret_manifest(employee_id: str, department: str, password: str) -> str:
    """Build the k8s secret manifest for the workspace password."""
    encoded = base64.b64encode(password.encode()).decode()
    return f"""apiVersion: v1
kind: Secret
metadata:
  name: {employee_id}-workspace-secret
  namespace: {department}
type: Opaque
data:
  password: {encoded}
"""


def commit_files(repo, files: dict, message: str, branch: str = "main"):
    """
    Commit multiple files to GitHub in a single commit.
    files = {path: content_string}
    """
    ref = repo.get_git_ref(f"heads/{branch}")
    base_tree = repo.get_git_tree(ref.object.sha, recursive=True)

    elements = []
    for path, content in files.items():
        blob = repo.create_git_blob(content, "utf-8")
        elements.append(InputGitTreeElement(
            path=path,
            mode="100644",
            type="blob",
            sha=blob.sha,
        ))

    new_tree = repo.create_git_tree(elements, base_tree)
    parent = repo.get_git_commit(ref.object.sha)
    commit = repo.create_git_commit(message, new_tree, [parent])
    ref.edit(commit.sha)


@functions_framework.http
def handle_hr_event(request):
    """
    HTTP trigger — expects JSON body:
    Onboard: {"action": "onboard", "employee_id": "emp-001", "department": "software"}
    Offboard: {"action": "offboard", "employee_id": "emp-001", "department": "software"}
    """
    try:
        data = request.get_json()
        action = data.get("action")
        employee_id = data.get("employee_id")
        department = data.get("department")
        project = os.environ["GOOGLE_CLOUD_PROJECT"]
        env = os.environ.get("ENV", "dev")
        github_repo = os.environ["GITHUB_REPO"]

        if not all([action, employee_id, department]):
            return {"error": "Missing required fields"}, 400

        token = get_github_token()
        g = Github(token)
        repo = g.get_repo(github_repo)

        workspace_path = f"k8s/workspaces/{department}/{employee_id}"

        if action == "onboard":
            password = generate_password()
            workspace_manifest = build_workspace_manifest(
                employee_id, department, project, env
            )
            secret_manifest = build_secret_manifest(
                employee_id, department, password
            )

            commit_files(
                repo,
                files={
                    f"{workspace_path}/workspace.yaml": workspace_manifest,
                    f"{workspace_path}/secret.yaml": secret_manifest,
                },
                message=f"chore: onboard {employee_id} to {department} [skip ci]"
            )
            return {"status": "onboarded", "employee_id": employee_id}, 200

        elif action == "offboard":
            # Delete both files in one commit
            ref = repo.get_git_ref("heads/main")
            base_tree = repo.get_git_tree(ref.object.sha, recursive=True)

            # Build new tree without the employee's files
            new_blobs = [
                InputGitTreeElement(path=e.path, mode="100644", type="blob", sha=e.sha)
                for e in base_tree.tree
                if not e.path.startswith(workspace_path)
                and e.type == "blob"
            ]

            new_tree = repo.create_git_tree(new_blobs)
            parent = repo.get_git_commit(ref.object.sha)
            commit = repo.create_git_commit(
                f"chore: offboard {employee_id} from {department} [skip ci]",
                new_tree,
                [parent]
            )
            ref.edit(commit.sha)
            return {"status": "offboarded", "employee_id": employee_id}, 200

        else:
            return {"error": f"Unknown action: {action}"}, 400

    except Exception as e:
        return {"error": str(e)}, 500