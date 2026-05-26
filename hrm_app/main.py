import os
import uuid
import asyncio
import bcrypt
import httpx
import asyncpg
import websockets
from fastapi import FastAPI, HTTPException, Request, Response, WebSocket
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from pydantic import BaseModel
from google.cloud import secretmanager


app = FastAPI(title="HRM Platform", redirect_slashes=False)
app.mount("/static", StaticFiles(directory="static"), name="static")

# ── Config ────────────────────────────────────────────────────────────────────

CLOUD_FUNCTION_URL = os.environ["CLOUD_FUNCTION_URL"]
DB_HOST            = os.environ.get("DB_HOST", "127.0.0.1")
DB_PORT            = int(os.environ.get("DB_PORT", 5432))
DB_NAME            = os.environ.get("DB_NAME", "hrm")
DB_USER            = os.environ.get("DB_USER", "hrm_app")
PROJECT_ID         = os.environ["GOOGLE_CLOUD_PROJECT"]
SECRET_ID          = os.environ.get("DB_PASSWORD_SECRET_ID", "dev-db-password")
SESSION_SECRET     = os.environ.get("SESSION_SECRET", "change-me-in-production")
SESSION_MAX_AGE    = 8 * 3600  # 8 hours

_signer = URLSafeTimedSerializer(SESSION_SECRET)

COOKIE_NAME = "workspace_session"

LOGIN_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Workspace Login — HRM</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
           background: #f5f5f5; display: flex; justify-content: center;
           align-items: center; min-height: 100vh; }
    .card { background: white; border-radius: 8px; padding: 32px;
            box-shadow: 0 2px 8px rgba(0,0,0,.15); width: 360px; }
    h1 { font-size: 18px; color: #1a73e8; margin-bottom: 24px; text-align: center; }
    label { display: block; font-size: 13px; color: #555; margin-bottom: 4px; }
    input { width: 100%; padding: 9px 12px; border: 1px solid #ddd;
            border-radius: 4px; font-size: 14px; margin-bottom: 16px; }
    input:focus { outline: none; border-color: #1a73e8; }
    button { width: 100%; padding: 10px; background: #1a73e8; color: white;
             border: none; border-radius: 4px; font-size: 14px; cursor: pointer; }
    button:hover { background: #1557b0; }
    .error { color: #d93025; font-size: 13px; margin-bottom: 12px; text-align: center; }
  </style>
</head>
<body>
<div class="card">
  <h1>Workspace Login</h1>
  <div class="error" id="err" style="display:none"></div>
  <label>Employee ID</label>
  <input id="eid" placeholder="emp-xxxxxxxx" autocomplete="username" />
  <label>Password</label>
  <input id="pwd" type="password" autocomplete="current-password" />
  <button onclick="login()">Sign In</button>
</div>
<script>
  document.addEventListener('keydown', e => { if (e.key === 'Enter') login(); });
  async function login() {
    const eid = document.getElementById('eid').value.trim();
    const pwd = document.getElementById('pwd').value;
    const err = document.getElementById('err');
    err.style.display = 'none';
    const resp = await fetch('/workspace/_auth', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ employee_id: eid, password: pwd }),
    });
    if (resp.ok) {
      window.location.href = '/workspace/';
    } else {
      const data = await resp.json().catch(() => ({}));
      err.textContent = data.detail || 'Login failed';
      err.style.display = 'block';
    }
  }
</script>
</body>
</html>"""


# ── Helpers ───────────────────────────────────────────────────────────────────

async def get_id_token(audience: str) -> str:
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity",
            params={"audience": audience},
            headers={"Metadata-Flavor": "Google"},
        )
        resp.raise_for_status()
        return resp.text


async def get_db_password() -> str:
    client = secretmanager.SecretManagerServiceClient()
    name   = f"projects/{PROJECT_ID}/secrets/{SECRET_ID}/versions/latest"
    return client.access_secret_version(request={"name": name}).payload.data.decode()


async def get_db_pool():
    password = await get_db_password()
    for attempt in range(10):
        try:
            return await asyncpg.create_pool(
                host=DB_HOST, port=DB_PORT,
                database=DB_NAME, user=DB_USER, password=password,
                min_size=2, max_size=10,
                ssl=False,
            )
        except Exception:
            if attempt == 9:
                raise
            await asyncio.sleep(3)


def sign_session(employee_id: str) -> str:
    return _signer.dumps({"employee_id": employee_id})


def verify_session(token: str) -> str | None:
    """Returns employee_id or None if invalid/expired."""
    try:
        data = _signer.loads(token, max_age=SESSION_MAX_AGE)
        return data.get("employee_id")
    except (BadSignature, SignatureExpired):
        return None


async def get_workspace_for_session(request: Request) -> dict:
    token = request.cookies.get(COOKIE_NAME)
    if not token:
        raise HTTPException(401, "Not authenticated")
    employee_id = verify_session(token)
    if not employee_id:
        raise HTTPException(401, "Session expired")
    async with app.state.db.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT employee_id, department FROM employees WHERE employee_id = $1 AND status = 'active'",
            employee_id,
        )
    if not row:
        raise HTTPException(403, "No active workspace for this account")
    return row


# ── Startup ───────────────────────────────────────────────────────────────────

@app.on_event("startup")
async def startup():
    app.state.db = await get_db_pool()
    async with app.state.db.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS employees (
                id            SERIAL PRIMARY KEY,
                employee_id   VARCHAR(50) UNIQUE NOT NULL,
                name          VARCHAR(100) NOT NULL,
                email         VARCHAR(100) UNIQUE NOT NULL,
                department    VARCHAR(50) NOT NULL,
                status        VARCHAR(20) DEFAULT 'active',
                password_hash VARCHAR(100),
                created_at    TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        await conn.execute("""
            ALTER TABLE employees ADD COLUMN IF NOT EXISTS password_hash VARCHAR(100)
        """)


# ── Models ────────────────────────────────────────────────────────────────────

class Employee(BaseModel):
    name: str
    email: str
    department: str   # software | devops | db-engineering


class WorkspaceLogin(BaseModel):
    employee_id: str
    password: str


# ── Routes ───────────────────────────────────────────────────────────────────

@app.get("/")
async def root():
    return FileResponse("static/index.html")


@app.get("/api/employees")
async def list_employees():
    async with app.state.db.acquire() as conn:
        rows = await conn.fetch(
            "SELECT * FROM employees WHERE status = 'active' ORDER BY created_at DESC"
        )
    return [dict(r) for r in rows]


@app.post("/api/employees")
async def onboard_employee(employee: Employee):
    employee_id = f"emp-{uuid.uuid4().hex[:8]}"

    # 1. Trigger Cloud Function first so we get the password back
    token = await get_id_token(CLOUD_FUNCTION_URL)
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            CLOUD_FUNCTION_URL,
            json={
                "action": "onboard",
                "employee_id": employee_id,
                "department": employee.department,
            },
            headers={"Authorization": f"Bearer {token}"},
            timeout=30.0,
        )
        if resp.status_code != 200:
            raise HTTPException(500, f"Workspace provisioning failed: {resp.text}")

    fn_data  = resp.json()
    password = fn_data.get("password", "")
    pw_hash  = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

    # 2. Save to database
    async with app.state.db.acquire() as conn:
        existing = await conn.fetchrow(
            "SELECT status FROM employees WHERE email = $1",
            employee.email,
        )
        if existing:
            if existing["status"] == "active":
                raise HTTPException(400, "Employee already exists")
            await conn.execute("""
                UPDATE employees
                SET employee_id = $1, name = $2, department = $3,
                    status = 'active', password_hash = $4, created_at = NOW()
                WHERE email = $5
            """, employee_id, employee.name, employee.department, pw_hash, employee.email)
        else:
            await conn.execute("""
                INSERT INTO employees (employee_id, name, email, department, password_hash)
                VALUES ($1, $2, $3, $4, $5)
            """, employee_id, employee.name, employee.email, employee.department, pw_hash)

    return {
        "status": "onboarded",
        "employee_id": employee_id,
        "workspace_url": f"/workspace/",
        "password": password,
    }


@app.delete("/api/employees/{employee_id}")
async def offboard_employee(employee_id: str):
    async with app.state.db.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT department FROM employees WHERE employee_id = $1 AND status = 'active'",
            employee_id,
        )
        if not row:
            raise HTTPException(404, "Employee not found")

        await conn.execute("""
            UPDATE employees SET status = 'offboarded' WHERE employee_id = $1
        """, employee_id)

    token = await get_id_token(CLOUD_FUNCTION_URL)
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            CLOUD_FUNCTION_URL,
            json={
                "action": "offboard",
                "employee_id": employee_id,
                "department": row["department"],
            },
            headers={"Authorization": f"Bearer {token}"},
            timeout=30.0,
        )
        if resp.status_code != 200:
            raise HTTPException(500, f"Workspace teardown failed: {resp.text}")

    return {"status": "offboarded", "employee_id": employee_id}


# ── Workspace auth ────────────────────────────────────────────────────────────

@app.get("/workspace")
@app.get("/workspace/")
async def workspace_root(request: Request):
    token = request.cookies.get(COOKIE_NAME)
    if token and verify_session(token):
        # Already logged in — let the proxy handle it
        return await proxy_workspace_http(request, "")
    return HTMLResponse(LOGIN_HTML)


@app.post("/workspace/_auth")
async def workspace_auth(creds: WorkspaceLogin, response: Response):
    async with app.state.db.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT employee_id, password_hash FROM employees WHERE employee_id = $1 AND status = 'active'",
            creds.employee_id,
        )
    if not row or not row["password_hash"]:
        raise HTTPException(401, "Invalid employee ID or password")
    loop = asyncio.get_event_loop()
    valid = await loop.run_in_executor(
        None, bcrypt.checkpw, creds.password.encode(), row["password_hash"].encode()
    )
    if not valid:
        raise HTTPException(401, "Invalid employee ID or password")

    cookie = sign_session(row["employee_id"])
    response.set_cookie(
        COOKIE_NAME,
        cookie,
        max_age=SESSION_MAX_AGE,
        httponly=True,
        samesite="lax",
        secure=True,
    )
    return {"status": "ok"}


@app.post("/workspace/_logout")
async def workspace_logout(response: Response):
    response.delete_cookie(COOKIE_NAME)
    return RedirectResponse("/workspace", status_code=303)


# ── Workspace proxy ───────────────────────────────────────────────────────────

@app.api_route(
    "/workspace/{path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"],
)
async def proxy_workspace_http(request: Request, path: str = ""):
    token = request.cookies.get(COOKIE_NAME)
    if not token or not verify_session(token):
        return HTMLResponse(LOGIN_HTML, status_code=401)

    row = await get_workspace_for_session(request)
    target = f"http://{row['employee_id']}-workspace.{row['department']}.svc.cluster.local:8080/{path}"
    if request.url.query:
        target += f"?{request.url.query}"

    excluded_req = {"host", "x-goog-authenticated-user-email", "x-goog-iap-jwt-assertion"}
    forward_headers = {k: v for k, v in request.headers.items() if k.lower() not in excluded_req}

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            proxy_resp = await client.request(
                method=request.method,
                url=target,
                headers=forward_headers,
                content=await request.body(),
            )
    except httpx.ConnectError:
        return HTMLResponse(
            "<h1>Workspace unavailable</h1><p>Your workspace pod is not reachable. "
            "It may still be starting — wait 30 seconds and refresh.</p>",
            status_code=503,
        )
    except httpx.TimeoutException:
        return HTMLResponse(
            "<h1>Workspace timeout</h1><p>Connection to your workspace timed out. Try refreshing.</p>",
            status_code=504,
        )

    excluded_resp = {"transfer-encoding", "connection"}
    resp_headers = {k: v for k, v in proxy_resp.headers.items() if k.lower() not in excluded_resp}
    return Response(content=proxy_resp.content, status_code=proxy_resp.status_code, headers=resp_headers)


@app.websocket("/workspace/{path:path}")
async def proxy_workspace_ws(websocket: WebSocket, path: str):
    token = websocket.cookies.get(COOKIE_NAME)
    if not token or not verify_session(token):
        await websocket.close(code=4401)
        return

    row = await get_workspace_for_session(websocket)
    target = f"ws://{row['employee_id']}-workspace.{row['department']}.svc.cluster.local:8080/{path}"
    if websocket.url.query:
        target += f"?{websocket.url.query}"

    await websocket.accept()
    try:
        async with websockets.connect(target) as ws_target:
            async def to_target():
                try:
                    async for msg in websocket.iter_bytes():
                        await ws_target.send(msg)
                except Exception:
                    pass

            async def to_client():
                try:
                    async for msg in ws_target:
                        if isinstance(msg, bytes):
                            await websocket.send_bytes(msg)
                        else:
                            await websocket.send_text(msg)
                except Exception:
                    pass

            await asyncio.gather(to_target(), to_client())
    except Exception:
        await websocket.close()


@app.get("/api/health")
async def health():
    return {"status": "ok"}
