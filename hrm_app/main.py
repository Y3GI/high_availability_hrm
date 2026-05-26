import os
import uuid
import asyncio
import httpx
import asyncpg
import websockets
from fastapi import FastAPI, HTTPException, Request, WebSocket
from fastapi.responses import FileResponse, Response, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from google.cloud import secretmanager


app = FastAPI(title="HRM Platform")
app.mount("/static", StaticFiles(directory="static"), name="static")

# ── Config ────────────────────────────────────────────────────────────────────

CLOUD_FUNCTION_URL = os.environ["CLOUD_FUNCTION_URL"]
DB_HOST            = os.environ.get("DB_HOST", "127.0.0.1")
DB_PORT            = int(os.environ.get("DB_PORT", 5432))
DB_NAME            = os.environ.get("DB_NAME", "hrm")
DB_USER            = os.environ.get("DB_USER", "hrm_app")
PROJECT_ID         = os.environ["GOOGLE_CLOUD_PROJECT"]
SECRET_ID          = os.environ.get("DB_PASSWORD_SECRET_ID", "dev-db-password")


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


@app.on_event("startup")
async def startup():
    app.state.db = await get_db_pool()
    # Create employees table if it doesn't exist
    async with app.state.db.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS employees (
                id          SERIAL PRIMARY KEY,
                employee_id VARCHAR(50) UNIQUE NOT NULL,
                name        VARCHAR(100) NOT NULL,
                email       VARCHAR(100) UNIQUE NOT NULL,
                department  VARCHAR(50) NOT NULL,
                status      VARCHAR(20) DEFAULT 'active',
                created_at  TIMESTAMPTZ DEFAULT NOW()
            )
        """)


# ── Models ────────────────────────────────────────────────────────────────────

class Employee(BaseModel):
    name: str
    email: str
    department: str   # software | devops | db-engineering


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

    # 1. Save to database
    async with app.state.db.acquire() as conn:
        existing = await conn.fetchrow(
            "SELECT status FROM employees WHERE email = $1",
            employee.email
        )
        if existing:
            if existing["status"] == "active":
                raise HTTPException(400, "Employee already exists")
            await conn.execute("""
                UPDATE employees
                SET employee_id = $1, name = $2, department = $3,
                    status = 'active', created_at = NOW()
                WHERE email = $4
            """, employee_id, employee.name, employee.department, employee.email)
        else:
            await conn.execute("""
                INSERT INTO employees (employee_id, name, email, department)
                VALUES ($1, $2, $3, $4)
            """, employee_id, employee.name, employee.email, employee.department)

    # 2. Trigger Cloud Function to provision workspace
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
            timeout=30.0
        )
        if resp.status_code != 200:
            async with app.state.db.acquire() as conn:
                await conn.execute(
                    "DELETE FROM employees WHERE employee_id = $1",
                    employee_id
                )
            raise HTTPException(500, f"Workspace provisioning failed: {resp.text}")

    fn_data = resp.json()
    return {
        "status": "onboarded",
        "employee_id": employee_id,
        "workspace_url": f"/workspace/{employee_id}",
        "password": fn_data.get("password"),
    }


@app.delete("/api/employees/{employee_id}")
async def offboard_employee(employee_id: str):
    # 1. Get department before deleting
    async with app.state.db.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT department FROM employees WHERE employee_id = $1 AND status = 'active'",
            employee_id
        )
        if not row:
            raise HTTPException(404, "Employee not found")

        # Soft delete — keep record for audit
        await conn.execute("""
            UPDATE employees SET status = 'offboarded' WHERE employee_id = $1
        """, employee_id)

    # 2. Trigger Cloud Function to destroy workspace
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
            timeout=30.0
        )
        if resp.status_code != 200:
            raise HTTPException(500, f"Workspace teardown failed: {resp.text}")

    return {"status": "offboarded", "employee_id": employee_id}


async def get_workspace_for_request(headers) -> dict:
    raw = headers.get("x-goog-authenticated-user-email", "")
    email = raw.removeprefix("accounts.google.com:")
    if not email:
        raise HTTPException(401, "Not authenticated")
    async with app.state.db.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT employee_id, department FROM employees WHERE email = $1 AND status = 'active'",
            email
        )
    if not row:
        raise HTTPException(403, "No active workspace for your account")
    return row


@app.api_route("/workspace", methods=["GET"])
@app.api_route("/workspace/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"])
async def proxy_workspace_http(request: Request, path: str = ""):
    row = await get_workspace_for_request(request.headers)
    target = f"http://{row['employee_id']}-workspace.{row['department']}.svc.cluster.local:8080/{path}"
    if request.url.query:
        target += f"?{request.url.query}"

    forward_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in ("host", "x-goog-authenticated-user-email", "x-goog-iap-jwt-assertion")
    }

    async with httpx.AsyncClient(timeout=60.0) as client:
        proxy_resp = await client.request(
            method=request.method,
            url=target,
            headers=forward_headers,
            content=await request.body(),
        )

    excluded = {"transfer-encoding", "connection"}
    resp_headers = {k: v for k, v in proxy_resp.headers.items() if k.lower() not in excluded}
    return Response(content=proxy_resp.content, status_code=proxy_resp.status_code, headers=resp_headers)


@app.websocket("/workspace/{path:path}")
async def proxy_workspace_ws(websocket: WebSocket, path: str):
    row = await get_workspace_for_request(websocket.headers)
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