-- AYBAK Hospital Platform
-- PostgreSQL 16+ — core tenancy, identity, patient, consent, and audit.
-- Run through a migration tool as a database owner/migrator. Never run with an application login.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA public;
CREATE EXTENSION IF NOT EXISTS btree_gist SCHEMA public;
CREATE SCHEMA aybak;

SET LOCAL search_path = aybak, public;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

REVOKE ALL ON SCHEMA aybak FROM PUBLIC;

CREATE FUNCTION aybak.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid
$$;

COMMENT ON FUNCTION aybak.current_tenant_id() IS
'Trusted backend sets SET LOCAL app.tenant_id after authorization. Missing/empty context returns NULL; malformed UUID fails closed.';

CREATE FUNCTION aybak.current_staff_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.staff_id', true), '')::uuid
$$;

CREATE FUNCTION aybak.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = clock_timestamp();
  NEW.updated_by = aybak.current_staff_id();
  RETURN NEW;
END
$$;

CREATE FUNCTION aybak.prevent_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION '% is append-only; create a correction/reversal instead', TG_TABLE_NAME
    USING ERRCODE = '55000';
END
$$;

CREATE FUNCTION aybak.enable_tenant_rls(target regclass)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, aybak, public
AS $$
BEGIN
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', target);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY', target);
  EXECUTE format(
    'CREATE POLICY tenant_isolation ON %s USING (tenant_id = aybak.current_tenant_id()) WITH CHECK (tenant_id = aybak.current_tenant_id())',
    target
  );
END
$$;

CREATE FUNCTION aybak.enable_audit_trigger(target regclass)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, aybak, public
AS $$
BEGIN
  EXECUTE format('CREATE TRIGGER audit_dml AFTER INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION aybak.audit_dml()', target);
END
$$;

CREATE TABLE organization (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL CHECK (code ~ '^[A-Za-z0-9][A-Za-z0-9._-]{1,62}$'),
  legal_name text NOT NULL CHECK (length(btrim(legal_name)) > 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','closed')),
  default_timezone text NOT NULL CHECK (length(default_timezone) > 0),
  data_residency text NOT NULL CHECK (length(data_residency) > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid
);

CREATE UNIQUE INDEX organization_code_uq ON organization (lower(code));

CREATE TABLE facility (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES organization(id),
  code text NOT NULL,
  name text NOT NULL CHECK (length(btrim(name)) > 0),
  facility_type text NOT NULL CHECK (facility_type IN ('hospital','clinic','laboratory','imaging_center','pharmacy','warehouse','administrative')),
  timezone text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','closed')),
  address jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(address) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, code)
);

CREATE TABLE department (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  facility_id uuid NOT NULL,
  parent_department_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  department_type text NOT NULL CHECK (department_type IN ('clinical','laboratory','radiology','pharmacy','billing','human_resources','inventory','administration')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, facility_id, code),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, parent_department_id) REFERENCES department(tenant_id, id),
  CHECK (parent_department_id IS NULL OR parent_department_id <> id)
);

CREATE TABLE staff_principal (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES organization(id),
  idp_issuer text NOT NULL,
  idp_subject text NOT NULL,
  display_name text NOT NULL,
  work_email text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('pending','active','suspended','terminated')),
  session_not_before timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (idp_issuer, idp_subject),
  CHECK (work_email IS NULL OR position('@' IN work_email) > 1)
);

CREATE TABLE practitioner (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  staff_id uuid NOT NULL,
  practitioner_type text NOT NULL CHECK (practitioner_type IN ('physician','nurse','pharmacist','pharmacy_technician','laboratory_technician','pathologist','radiologist','radiology_technician','other')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','inactive')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, staff_id),
  FOREIGN KEY (tenant_id, staff_id) REFERENCES staff_principal(tenant_id, id)
);

CREATE TABLE role_template (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES organization(id),
  code text NOT NULL,
  description text NOT NULL,
  policy_document jsonb NOT NULL CHECK (jsonb_typeof(policy_document) = 'object'),
  version integer NOT NULL CHECK (version > 0),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, code, version)
);

CREATE TABLE user_role_assignment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  staff_id uuid NOT NULL,
  role_template_id uuid NOT NULL,
  facility_id uuid,
  department_id uuid,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  approved_by uuid,
  approval_reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, staff_id) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, role_template_id) REFERENCES role_template(tenant_id, id),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, department_id) REFERENCES department(tenant_id, id),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);

CREATE TABLE worker_assignment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  staff_id uuid NOT NULL,
  facility_id uuid NOT NULL,
  department_id uuid,
  position_code text NOT NULL,
  employment_status text NOT NULL CHECK (employment_status IN ('active','leave','suspended','terminated')),
  valid_from date NOT NULL,
  valid_until date,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, staff_id) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, department_id) REFERENCES department(tenant_id, id),
  CHECK (valid_until IS NULL OR valid_until >= valid_from)
);

CREATE TABLE professional_credential (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  practitioner_id uuid NOT NULL,
  credential_type text NOT NULL,
  issuer text NOT NULL,
  identifier_value text NOT NULL,
  valid_from date NOT NULL,
  valid_until date,
  verification_status text NOT NULL CHECK (verification_status IN ('pending','verified','rejected','expired','revoked')),
  verified_at timestamptz,
  verified_by uuid,
  source_document_ref text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, credential_type, issuer, identifier_value),
  FOREIGN KEY (tenant_id, practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (valid_until IS NULL OR valid_until >= valid_from)
);

CREATE TABLE training_privilege (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  practitioner_id uuid NOT NULL,
  privilege_code text NOT NULL,
  valid_from date NOT NULL,
  valid_until date,
  status text NOT NULL CHECK (status IN ('active','suspended','expired','revoked')),
  evidence_ref text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (valid_until IS NULL OR valid_until >= valid_from)
);

CREATE TABLE patient (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES organization(id),
  birth_date date,
  administrative_gender text,
  sex_at_birth_code text,
  marital_status_code text,
  deceased_at timestamptz,
  preferred_language text,
  unidentified_patient boolean NOT NULL DEFAULT false,
  identity_verification_status text NOT NULL DEFAULT 'unverified' CHECK (identity_verification_status IN ('unverified','verified','pending_merge')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  CHECK (birth_date IS NULL OR birth_date <= CURRENT_DATE),
  CHECK (deceased_at IS NULL OR birth_date IS NULL OR deceased_at::date >= birth_date)
);

COMMENT ON TABLE patient IS 'Tenant-scoped identity spine. Do not store age; derive it from birth_date at the clinically relevant reference time.';

CREATE TABLE patient_identifier (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  identifier_type text NOT NULL CHECK (identifier_type IN ('mrn','national_id','passport','insurance','temporary','external')),
  issuer text NOT NULL,
  value_display text NOT NULL,
  value_normalized text NOT NULL CHECK (value_normalized = upper(btrim(value_normalized)) AND length(value_normalized) > 0),
  valid_from date,
  valid_until date,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','entered_in_error')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from)
);

CREATE UNIQUE INDEX patient_identifier_active_uq
  ON patient_identifier (tenant_id, issuer, identifier_type, value_normalized)
  WHERE status = 'active';
CREATE INDEX patient_identifier_patient_idx ON patient_identifier (tenant_id, patient_id, status);

CREATE TABLE person_name (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  use_code text NOT NULL DEFAULT 'official' CHECK (use_code IN ('official','usual','nickname','maiden','anonymous','old')),
  family_name text,
  given_names text[],
  prefix text,
  suffix text,
  display_text text NOT NULL,
  valid_from date,
  valid_until date,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from),
  CHECK (length(btrim(display_text)) > 0)
);

CREATE TABLE patient_contact_point (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  contact_type text NOT NULL CHECK (contact_type IN ('phone','email','fax','other')),
  use_code text NOT NULL DEFAULT 'home' CHECK (use_code IN ('home','work','temporary','mobile','emergency')),
  value text NOT NULL,
  is_primary boolean NOT NULL DEFAULT false,
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id)
);

CREATE UNIQUE INDEX patient_primary_contact_uq
  ON patient_contact_point (tenant_id, patient_id, contact_type, use_code)
  WHERE is_primary;

CREATE TABLE patient_address (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  use_code text NOT NULL DEFAULT 'home' CHECK (use_code IN ('home','work','temporary','old')),
  line text[],
  city text,
  district text,
  state_region text,
  postal_code text,
  country_code text CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$'),
  valid_from date,
  valid_until date,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id)
);

CREATE TABLE patient_link (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  source_patient_id uuid NOT NULL,
  target_patient_id uuid NOT NULL,
  link_type text NOT NULL CHECK (link_type IN ('merged_into','replaces','seealso')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','reverted','entered_in_error')),
  reason text NOT NULL,
  reviewed_by uuid NOT NULL,
  reviewed_at timestamptz NOT NULL DEFAULT now(),
  reversal_of_link_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, source_patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, target_patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, reviewed_by) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, reversal_of_link_id) REFERENCES patient_link(tenant_id, id),
  CHECK (source_patient_id <> target_patient_id)
);

CREATE INDEX patient_link_source_idx ON patient_link (tenant_id, source_patient_id, status);
CREATE INDEX patient_link_target_idx ON patient_link (tenant_id, target_patient_id, status);

CREATE TABLE identity_match_review (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  candidate_patient_id uuid NOT NULL,
  existing_patient_id uuid NOT NULL,
  match_method text NOT NULL CHECK (match_method IN ('deterministic','probabilistic','manual')),
  match_score numeric(5,4) CHECK (match_score BETWEEN 0 AND 1),
  evidence jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(evidence) = 'object'),
  decision text NOT NULL CHECK (decision IN ('pending','same_patient','different_patients','needs_more_evidence')),
  decided_by uuid,
  decided_at timestamptz,
  decision_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, candidate_patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, existing_patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, decided_by) REFERENCES staff_principal(tenant_id, id),
  CHECK (candidate_patient_id <> existing_patient_id),
  CHECK (match_method <> 'probabilistic' OR match_score IS NOT NULL),
  CHECK (decision = 'pending' OR (decided_by IS NOT NULL AND decided_at IS NOT NULL AND decision_reason IS NOT NULL))
);

CREATE TABLE consent_directive (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  directive_type text NOT NULL CHECK (directive_type IN ('permit','deny')),
  purpose_code text NOT NULL,
  scope_document jsonb NOT NULL CHECK (jsonb_typeof(scope_document) = 'object'),
  status text NOT NULL CHECK (status IN ('draft','active','inactive','rejected','entered_in_error')),
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  source_document_ref text,
  captured_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, captured_by) REFERENCES staff_principal(tenant_id, id),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);

CREATE INDEX consent_directive_lookup_idx ON consent_directive (tenant_id, patient_id, status, purpose_code, valid_from, valid_until);

CREATE TABLE care_relationship (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  practitioner_id uuid,
  facility_id uuid NOT NULL,
  relationship_type text NOT NULL CHECK (relationship_type IN ('attending','care_team','consulting','primary_care','emergency','department')),
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, practitioner_id) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);

CREATE INDEX care_relationship_access_idx ON care_relationship (tenant_id, practitioner_id, patient_id, valid_from, valid_until);
CREATE INDEX care_relationship_patient_idx ON care_relationship (tenant_id, patient_id, valid_until);

CREATE TABLE break_glass_session (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  staff_id uuid NOT NULL,
  patient_id uuid,
  reason text NOT NULL CHECK (length(btrim(reason)) >= 10),
  started_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  ended_at timestamptz,
  review_status text NOT NULL DEFAULT 'pending' CHECK (review_status IN ('pending','justified','unjustified','needs_investigation')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, staff_id) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, reviewed_by) REFERENCES staff_principal(tenant_id, id),
  CHECK (expires_at > started_at),
  CHECK (ended_at IS NULL OR ended_at >= started_at),
  CHECK (reviewed_at IS NULL OR reviewed_by IS NOT NULL)
);

CREATE TABLE audit_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES organization(id),
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_staff_id uuid,
  actor_subject text,
  actor_database_role text NOT NULL DEFAULT current_user,
  action text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE','READ','SEARCH','EXPORT','PRINT','LOGIN','LOGOUT','BREAK_GLASS','SIGN','VERIFY','OVERRIDE','SYNC')),
  resource_type text NOT NULL,
  resource_id uuid,
  patient_subject_id uuid,
  purpose_code text,
  outcome text NOT NULL DEFAULT 'success' CHECK (outcome IN ('success','failure','denied','partial')),
  changed_fields text[],
  details jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(details) = 'object'),
  correlation_id text,
  causation_id text,
  request_id text,
  source_ip inet,
  break_glass_session_id uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, actor_staff_id) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_subject_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, break_glass_session_id) REFERENCES break_glass_session(tenant_id, id)
);

COMMENT ON TABLE audit_event IS 'Restricted append-only audit. changed_fields stores field names, not values. details must use an approved non-PHI allowlist.';

CREATE INDEX audit_event_subject_time_idx ON audit_event (tenant_id, patient_subject_id, occurred_at DESC);
CREATE INDEX audit_event_resource_time_idx ON audit_event (tenant_id, resource_type, resource_id, occurred_at DESC);
CREATE INDEX audit_event_actor_time_idx ON audit_event (tenant_id, actor_staff_id, occurred_at DESC);
CREATE INDEX audit_event_correlation_idx ON audit_event (tenant_id, correlation_id, occurred_at);
CREATE INDEX audit_event_time_brin ON audit_event USING brin (occurred_at);

CREATE TABLE access_export (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  requested_by uuid NOT NULL,
  patient_id uuid,
  export_type text NOT NULL CHECK (export_type IN ('patient_access','clinical_handoff','billing','legal','reporting')),
  purpose_code text NOT NULL,
  scope_document jsonb NOT NULL CHECK (jsonb_typeof(scope_document) = 'object'),
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','approved','generating','ready','downloaded','expired','revoked','rejected')),
  object_storage_key text,
  content_hash text,
  encryption_key_ref text,
  expires_at timestamptz,
  downloaded_at timestamptz,
  approved_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, requested_by) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, approved_by) REFERENCES staff_principal(tenant_id, id),
  CHECK (status <> 'ready' OR (object_storage_key IS NOT NULL AND content_hash IS NOT NULL AND expires_at IS NOT NULL)),
  CHECK (status <> 'downloaded' OR downloaded_at IS NOT NULL)
);

CREATE INDEX access_export_requester_idx ON access_export (tenant_id, requested_by, created_at DESC);

CREATE FUNCTION aybak.audit_dml()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, aybak, public
AS $$
DECLARE
  v_tenant uuid;
  v_resource uuid;
  v_patient uuid;
  v_changed text[];
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF TG_TABLE_NAME = 'organization' THEN v_tenant := OLD.id; ELSE v_tenant := OLD.tenant_id; END IF;
    v_resource := OLD.id;
    IF to_jsonb(OLD) ? 'patient_id' THEN v_patient := (to_jsonb(OLD)->>'patient_id')::uuid; END IF;
    IF TG_TABLE_NAME = 'patient' THEN v_patient := OLD.id; END IF;
    SELECT array_agg(key ORDER BY key) INTO v_changed FROM jsonb_object_keys(to_jsonb(OLD)) AS key;
  ELSE
    IF TG_TABLE_NAME = 'organization' THEN v_tenant := NEW.id; ELSE v_tenant := NEW.tenant_id; END IF;
    v_resource := NEW.id;
    IF to_jsonb(NEW) ? 'patient_id' THEN v_patient := (to_jsonb(NEW)->>'patient_id')::uuid; END IF;
    IF TG_TABLE_NAME = 'patient' THEN v_patient := NEW.id; END IF;
    IF TG_OP = 'INSERT' THEN
      SELECT array_agg(key ORDER BY key) INTO v_changed FROM jsonb_object_keys(to_jsonb(NEW)) AS key;
    ELSE
      SELECT array_agg(n.key ORDER BY n.key) INTO v_changed
      FROM jsonb_each(to_jsonb(NEW)) n
      WHERE to_jsonb(OLD) -> n.key IS DISTINCT FROM n.value;
    END IF;
  END IF;

  INSERT INTO aybak.audit_event (
    tenant_id, actor_staff_id, actor_subject, action, resource_type, resource_id,
    patient_subject_id, purpose_code, changed_fields, correlation_id, request_id
  ) VALUES (
    v_tenant, aybak.current_staff_id(), NULLIF(current_setting('app.actor_subject', true), ''),
    TG_OP, TG_TABLE_NAME, v_resource, v_patient,
    NULLIF(current_setting('app.purpose', true), ''), v_changed,
    NULLIF(current_setting('app.correlation_id', true), ''),
    NULLIF(current_setting('app.request_id', true), '')
  );
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END
$$;

CREATE FUNCTION aybak.record_access_audit(
  p_action text,
  p_resource_type text,
  p_resource_id uuid,
  p_patient_id uuid DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, aybak, public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_action NOT IN ('READ','SEARCH','EXPORT','PRINT','LOGIN','LOGOUT','BREAK_GLASS','SYNC') THEN
    RAISE EXCEPTION 'Unsupported access audit action: %', p_action;
  END IF;
  IF p_details IS NULL OR jsonb_typeof(p_details) <> 'object' OR octet_length(p_details::text) > 8192 THEN
    RAISE EXCEPTION 'Audit details must be a bounded JSON object';
  END IF;
  INSERT INTO aybak.audit_event (
    tenant_id, actor_staff_id, actor_subject, action, resource_type, resource_id,
    patient_subject_id, purpose_code, details, correlation_id, request_id
  ) VALUES (
    aybak.current_tenant_id(), aybak.current_staff_id(), NULLIF(current_setting('app.actor_subject', true), ''),
    p_action, p_resource_type, p_resource_id, p_patient_id,
    NULLIF(current_setting('app.purpose', true), ''), p_details,
    NULLIF(current_setting('app.correlation_id', true), ''),
    NULLIF(current_setting('app.request_id', true), '')
  ) RETURNING id INTO v_id;
  RETURN v_id;
END
$$;

-- Generic updated-at maintenance applies only to tables that expose updated_at.
DO $$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT c.oid::regclass AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'updated_at' AND NOT a.attisdropped
    WHERE n.nspname = 'aybak' AND c.relkind = 'r'
  LOOP
    EXECUTE format('CREATE TRIGGER set_updated_at BEFORE UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION aybak.set_updated_at()', t.table_name);
  END LOOP;
END
$$;

-- Enable and force RLS on every tenant-owned table created by this migration.
DO $$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT c.oid::regclass AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped
    WHERE n.nspname = 'aybak' AND c.relkind = 'r'
  LOOP
    PERFORM aybak.enable_tenant_rls(t.table_name);
  END LOOP;
END
$$;

ALTER TABLE organization ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization FORCE ROW LEVEL SECURITY;
CREATE POLICY organization_isolation ON organization
  USING (id = aybak.current_tenant_id()) WITH CHECK (id = aybak.current_tenant_id());

-- Clinical/security changes are audited without copying before/after PHI into audit JSON.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'organization','facility','department','staff_principal','practitioner','role_template',
    'user_role_assignment','worker_assignment','professional_credential','training_privilege',
    'patient','patient_identifier','person_name','patient_contact_point','patient_address',
    'patient_link','identity_match_review','consent_directive','care_relationship',
    'break_glass_session','access_export'
  ] LOOP
    EXECUTE format('SELECT aybak.enable_audit_trigger(%L::regclass)', 'aybak.' || t);
  END LOOP;
END
$$;

CREATE TRIGGER audit_event_immutable BEFORE UPDATE OR DELETE ON audit_event
  FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA aybak FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA aybak FROM PUBLIC;

COMMIT;
