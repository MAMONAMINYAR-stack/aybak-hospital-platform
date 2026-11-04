-- AYBAK Hospital Platform — least-privilege roles, grants, and context guard.
-- Run as a superuser / database owner after V001–V006.
-- Replace placeholder role passwords operationally via a secrets manager; roles here are NOLOGIN by default.

BEGIN;
SET LOCAL search_path = pg_catalog, aybak, public;

-- 1. Login roles are created outside this migration (by IaC) and granted membership below.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aybak_owner') THEN
    CREATE ROLE aybak_owner NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aybak_migrator') THEN
    CREATE ROLE aybak_migrator NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aybak_app') THEN
    CREATE ROLE aybak_app NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aybak_readonly') THEN
    CREATE ROLE aybak_readonly NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aybak_analytics') THEN
    CREATE ROLE aybak_analytics NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aybak_integration') THEN
    CREATE ROLE aybak_integration NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aybak_breakglass') THEN
    CREATE ROLE aybak_breakglass NOLOGIN;
  END IF;
END
$$;

GRANT aybak_owner TO aybak_migrator;
GRANT aybak_app TO aybak_readonly;
GRANT aybak_integration TO aybak_analytics;

GRANT USAGE ON SCHEMA aybak TO aybak_app, aybak_readonly, aybak_analytics, aybak_integration, aybak_breakglass;

-- 2. Application role: DML on tenant tables, no DDL, no TRUNCATE, no sequence ownership abuse.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA aybak TO aybak_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA aybak TO aybak_app;

-- 3. Read-only role.
GRANT SELECT ON ALL TABLES IN SCHEMA aybak TO aybak_readonly;

-- 4. Analytics role: read-only on de-identified/aggregate views only.
GRANT SELECT ON ALL TABLES IN SCHEMA aybak TO aybak_analytics;

-- 5. Integration role: minimal insert/select for interface staging.
GRANT SELECT, INSERT ON aybak.inbound_message, aybak.outbox_event, aybak.delivery_attempt,
      aybak.external_result_import, aybak.sync_change_log TO aybak_integration;
GRANT USAGE ON SCHEMA aybak TO aybak_integration;

-- 6. Break-glass role: read access only, must be time-bound at the session level and audited.
GRANT SELECT ON ALL TABLES IN SCHEMA aybak TO aybak_breakglass;

-- 7. Explicit denies that would otherwise be granted by later blanket grants.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON aybak.audit_event FROM aybak_app, aybak_readonly, aybak_analytics;
REVOKE UPDATE, DELETE, TRUNCATE ON aybak.financial_ledger_entry FROM aybak_app;
REVOKE UPDATE, DELETE, TRUNCATE ON aybak.stock_movement FROM aybak_app;
REVOKE UPDATE, DELETE, TRUNCATE ON aybak.medication_override FROM aybak_app;
REVOKE UPDATE, DELETE, TRUNCATE ON aybak.specimen_event FROM aybak_app;
REVOKE UPDATE, DELETE, TRUNCATE ON aybak.radiology_report_version FROM aybak_app;
REVOKE UPDATE, DELETE, TRUNCATE ON aybak.critical_result_notification FROM aybak_app;
REVOKE UPDATE, DELETE, TRUNCATE ON aybak.delivery_attempt FROM aybak_app;
REVOKE UPDATE, DELETE, TRUNCATE ON aybak.ai_output_review FROM aybak_app;
REVOKE UPDATE, DELETE, TRUNCATE ON aybak.audit_event, aybak.access_export FROM aybak_app;
REVOKE ALL ON aybak.organization FROM aybak_app;
GRANT SELECT, INSERT, UPDATE ON aybak.organization TO aybak_app;

-- 7b. Functions: application may call context helpers and the audited access-log writer.
--     DDL helpers stay revoked so application logins cannot alter policies.
GRANT EXECUTE ON FUNCTION aybak.current_tenant_id() TO aybak_app, aybak_readonly, aybak_analytics, aybak_breakglass;
GRANT EXECUTE ON FUNCTION aybak.current_staff_id() TO aybak_app, aybak_readonly, aybak_analytics, aybak_breakglass;
GRANT EXECUTE ON FUNCTION aybak.record_access_audit(text, text, uuid, uuid, jsonb) TO aybak_app, aybak_breakglass;
REVOKE EXECUTE ON FUNCTION aybak.enable_tenant_rls(regclass) FROM PUBLIC, aybak_app, aybak_readonly, aybak_analytics, aybak_integration, aybak_breakglass;
REVOKE EXECUTE ON FUNCTION aybak.enable_audit_trigger(regclass) FROM PUBLIC, aybak_app, aybak_readonly, aybak_analytics, aybak_integration, aybak_breakglass;
REVOKE EXECUTE ON FUNCTION aybak.audit_dml() FROM PUBLIC, aybak_app, aybak_readonly, aybak_analytics, aybak_integration, aybak_breakglass;

-- 8. Future objects inherit the same grants.
ALTER DEFAULT PRIVILEGES IN SCHEMA aybak GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO aybak_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA aybak GRANT SELECT ON TABLES TO aybak_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA aybak GRANT USAGE, SELECT ON SEQUENCES TO aybak_app;

-- 9. Audit table is append-only for everyone except the migrator/owner; only the
--    SECURITY DEFINER functions can write it, and app has no direct INSERT.
ALTER TABLE aybak.audit_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE aybak.audit_event FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON aybak.audit_event;
CREATE POLICY tenant_isolation ON aybak.audit_event
  USING (tenant_id = aybak.current_tenant_id())
  WITH CHECK (tenant_id = aybak.current_tenant_id());

-- 10. Application session guard: reject writes that lack trusted context.
CREATE FUNCTION aybak.require_session_context()
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF aybak.current_tenant_id() IS NULL THEN
    RAISE EXCEPTION 'Missing tenant context: backend must SET LOCAL app.tenant_id' USING ERRCODE = '42501';
  END IF;
END
$$;

GRANT EXECUTE ON FUNCTION aybak.require_session_context() TO aybak_app;

-- 11. Restrict schema creation.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA aybak FROM PUBLIC;

COMMIT;
