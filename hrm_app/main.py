import os
import httpx
import asyncpg
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
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


async def get_db_password() -> str:
    client = secretmanager.SecretManagerServiceClient()
    name   = f"projects/{PROJECT_ID}/secrets/{SECRET_ID}/versions/latest"
    return client.access_secret_version(request={"name": name}).payload.data.decode()


async def get_db_pool():
    password = await get_db_password()
    return await asyncpg.create_pool(
        host=DB_HOST, port=DB_PORT,
        database=DB_NAME, user=DB_USER, password=password,
        min_size=2, max_size=10,
        ssl=False,
    )


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
    employee_id: str
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
    # 1. Save to database
    async with app.state.db.acquire() as conn:
        existing = await conn.fetchrow(
            "SELECT id FROM employees WHERE employee_id = $1",
            employee.employee_id
        )
        if existing:
            raise HTTPException(400, "Employee already exists")

        await conn.execute("""
            INSERT INTO employees (employee_id, name, email, department)
            VALUES ($1, $2, $3, $4)
        """, employee.employee_id, employee.name, employee.email, employee.department)

    # 2. Trigger Cloud Function to provision workspace
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            CLOUD_FUNCTION_URL,
            json={
                "action": "onboard",
                "employee_id": employee.employee_id,
                "department": employee.department,
            },
            timeout=30.0
        )
        if resp.status_code != 200:
            # Rollback DB insert if function fails
            async with app.state.db.acquire() as conn:
                await conn.execute(
                    "DELETE FROM employees WHERE employee_id = $1",
                    employee.employee_id
                )
            raise HTTPException(500, f"Workspace provisioning failed: {resp.text}")

    return {"status": "onboarded", "employee_id": employee.employee_id}


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
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            CLOUD_FUNCTION_URL,
            json={
                "action": "offboard",
                "employee_id": employee_id,
                "department": row["department"],
            },
            timeout=30.0
        )
        if resp.status_code != 200:
            raise HTTPException(500, f"Workspace teardown failed: {resp.text}")

    return {"status": "offboarded", "employee_id": employee_id}


@app.get("/api/health")
async def health():
    return {"status": "ok"}