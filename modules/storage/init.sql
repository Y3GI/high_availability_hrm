-- Idempotent role creation — safe to run multiple times
DO $$
BEGIN
  -- DevOps: read-only for debugging
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'devops_readonly') THEN
    CREATE ROLE devops_readonly;
  END IF;
  GRANT CONNECT ON DATABASE hrm TO devops_readonly;
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO devops_readonly;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO devops_readonly;

  -- DB Engineers: full access
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'db_engineer') THEN
    CREATE ROLE db_engineer;
  END IF;
  GRANT ALL PRIVILEGES ON DATABASE hrm TO db_engineer;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES TO db_engineer;

  -- App user: minimum required
  GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA public TO hrm_app;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO hrm_app;
END
$$;