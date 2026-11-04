-- AYBAK Hospital Platform — integration, interoperability, offline sync, and governed AI.
-- Requires V001–V005.

BEGIN;
SET LOCAL search_path = aybak, public;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

CREATE TABLE integration_endpoint (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  facility_id uuid,
  code text NOT NULL,
  display_name text NOT NULL,
  protocol text NOT NULL CHECK (protocol IN ('fhir_r4','hl7v2','dicom','rest','sftp','message_queue')),
  direction text NOT NULL CHECK (direction IN ('inbound','outbound','bidirectional')),
  base_url text,
  secret_reference text,
  status text NOT NULL CHECK (status IN ('active','paused','degraded','retired')),
  mapping_version text NOT NULL,
  last_success_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, code),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id)
);

CREATE TABLE inbound_message (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  integration_endpoint_id uuid NOT NULL,
  message_type text NOT NULL,
  message_control_id text NOT NULL,
  sender_identifier text,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  payload_hash text NOT NULL,
  payload_size_bytes integer NOT NULL CHECK (payload_size_bytes >= 0),
  object_storage_reference text NOT NULL,
  status text NOT NULL CHECK (status IN ('received','validated','processed','needs_review','rejected','duplicate')),
  rejection_reason text,
  processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, integration_endpoint_id, message_control_id),
  FOREIGN KEY (tenant_id, integration_endpoint_id) REFERENCES integration_endpoint(tenant_id, id),
  CHECK (status <> 'rejected' OR rejection_reason IS NOT NULL)
);

CREATE INDEX inbound_message_status_idx ON inbound_message (tenant_id, status, received_at);

CREATE TABLE outbox_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  aggregate_type text NOT NULL,
  aggregate_id uuid NOT NULL,
  event_type text NOT NULL,
  event_version integer NOT NULL CHECK (event_version > 0),
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  payload_reference text,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  published_at timestamptz,
  publish_attempts integer NOT NULL DEFAULT 0 CHECK (publish_attempts >= 0),
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, aggregate_type, aggregate_id, event_type, event_version)
);

COMMENT ON TABLE outbox_event IS 'Transactional outbox. Payload holds identifiers and non-PHI metadata only; PHI stays in the owning table or an encrypted object.';

CREATE INDEX outbox_unpublished_idx ON outbox_event (occurred_at) WHERE published_at IS NULL;
CREATE INDEX outbox_aggregate_idx ON outbox_event (tenant_id, aggregate_type, aggregate_id, occurred_at);

CREATE TABLE delivery_attempt (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  outbox_event_id uuid NOT NULL,
  destination text NOT NULL,
  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  attempted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  outcome text NOT NULL CHECK (outcome IN ('delivered','retryable_failure','permanent_failure')),
  http_status integer,
  error_detail text,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, outbox_event_id, destination, attempt_number),
  FOREIGN KEY (tenant_id, outbox_event_id) REFERENCES outbox_event(tenant_id, id)
);

CREATE TABLE sync_device (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  facility_id uuid NOT NULL,
  device_fingerprint text NOT NULL,
  assigned_staff_id uuid NOT NULL,
  platform text NOT NULL CHECK (platform IN ('ios','android','windows','web')),
  app_version text NOT NULL,
  encryption_key_reference text NOT NULL,
  enrolled_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_seen_at timestamptz,
  revoked_at timestamptz,
  status text NOT NULL CHECK (status IN ('enrolled','active','suspended','wiped','revoked')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, device_fingerprint),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, assigned_staff_id) REFERENCES staff_principal(tenant_id, id),
  CHECK (status <> 'revoked' OR revoked_at IS NOT NULL)
);

CREATE INDEX sync_device_staff_idx ON sync_device (tenant_id, assigned_staff_id, status);

CREATE TABLE sync_change_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  device_id uuid NOT NULL,
  direction text NOT NULL CHECK (direction IN ('push','pull')),
  ordinal bigint NOT NULL CHECK (ordinal > 0),
  resource_type text NOT NULL,
  resource_id uuid NOT NULL,
  operation text NOT NULL CHECK (operation IN ('create','update','delete')),
  client_version integer,
  server_version integer,
  payload_hash text NOT NULL,
  conflict_policy text NOT NULL CHECK (conflict_policy IN ('server_wins','client_wins','manual_review','field_merge')),
  outcome text NOT NULL CHECK (outcome IN ('applied','skipped','conflict','rejected')),
  rejection_reason text,
  patient_id uuid,
  client_recorded_at timestamptz,
  server_recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, device_id, direction, ordinal),
  FOREIGN KEY (tenant_id, device_id) REFERENCES sync_device(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  CHECK (outcome <> 'rejected' OR rejection_reason IS NOT NULL)
);

CREATE INDEX sync_change_log_device_idx ON sync_change_log (tenant_id, device_id, server_recorded_at);
CREATE INDEX sync_change_log_conflicts_idx ON sync_change_log (tenant_id, outcome, server_recorded_at) WHERE outcome = 'conflict';
CREATE INDEX sync_change_log_patient_idx ON sync_change_log (tenant_id, patient_id, server_recorded_at) WHERE patient_id IS NOT NULL;

CREATE TABLE ai_model_registration (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid,
  model_key text NOT NULL,
  model_version text NOT NULL,
  vendor text NOT NULL,
  intended_use text NOT NULL,
  risk_class text NOT NULL CHECK (risk_class IN ('administrative','clinical_decision_support','diagnostic','generative_documentation')),
  deployment text NOT NULL CHECK (deployment IN ('vendor_api','self_hosted','on_premise')),
  data_processing_agreement_reference text,
  phi_permitted boolean NOT NULL DEFAULT false,
  human_oversight_required boolean NOT NULL DEFAULT true,
  approval_status text NOT NULL CHECK (approval_status IN ('proposed','under_review','approved','approved_with_conditions','rejected','retired')),
  approved_by uuid,
  approved_at timestamptz,
  evaluation_report_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (id),
  UNIQUE (tenant_id, id),
  UNIQUE (model_key, model_version),
  FOREIGN KEY (tenant_id, approved_by) REFERENCES staff_principal(tenant_id, id),
  CHECK (approval_status NOT IN ('approved','approved_with_conditions') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL AND evaluation_report_reference IS NOT NULL)),
  CHECK (approval_status NOT IN ('approved','approved_with_conditions') OR human_oversight_required)
);

CREATE TABLE ai_inference_record (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  model_registration_id uuid NOT NULL,
  patient_id uuid,
  encounter_id uuid,
  purpose_code text NOT NULL,
  input_context_record_ids uuid[] NOT NULL DEFAULT '{}',
  input_hash text NOT NULL,
  prompt_template_version text NOT NULL,
  output_summary text,
  output_object_reference text,
  confidence numeric(5,4) CHECK (confidence >= 0 AND confidence <= 1),
  missing_context text[] NOT NULL DEFAULT '{}',
  latency_ms integer CHECK (latency_ms >= 0),
  status text NOT NULL CHECK (status IN ('requested','completed','failed','blocked','rejected_by_reviewer')),
  human_review_required boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, model_registration_id) REFERENCES ai_model_registration(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id)
);

CREATE INDEX ai_inference_patient_idx ON ai_inference_record (tenant_id, patient_id, created_at DESC);
CREATE INDEX ai_inference_model_idx ON ai_inference_record (tenant_id, model_registration_id, status, created_at);

CREATE TABLE ai_output_review (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  ai_inference_record_id uuid NOT NULL,
  reviewer_practitioner_id uuid NOT NULL,
  decision text NOT NULL CHECK (decision IN ('accepted','accepted_with_edits','rejected')),
  edited_output_hash text,
  reviewer_notes text,
  reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, ai_inference_record_id),
  FOREIGN KEY (tenant_id, ai_inference_record_id) REFERENCES ai_inference_record(tenant_id, id),
  FOREIGN KEY (tenant_id, reviewer_practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (decision <> 'accepted_with_edits' OR edited_output_hash IS NOT NULL)
);

CREATE TABLE ai_model_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  ai_output_review_id uuid NOT NULL,
  feedback_type text NOT NULL CHECK (feedback_type IN ('unsafe','incorrect','incomplete','bias','hallucination','other')),
  severity text NOT NULL CHECK (severity IN ('low','moderate','high','critical')),
  detail text NOT NULL,
  reported_to_vendor_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, ai_output_review_id) REFERENCES ai_output_review(tenant_id, id)
);

DO $$
DECLARE t record;
BEGIN
  FOR t IN SELECT c.oid::regclass AS table_name FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='updated_at' AND NOT a.attisdropped
    WHERE n.nspname='aybak' AND c.relkind='r' AND NOT EXISTS (
      SELECT 1 FROM pg_trigger g WHERE g.tgrelid=c.oid AND g.tgname='set_updated_at') LOOP
    EXECUTE format('CREATE TRIGGER set_updated_at BEFORE UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION aybak.set_updated_at()', t.table_name);
  END LOOP;
  FOR t IN SELECT c.oid::regclass AS table_name FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='tenant_id' AND NOT a.attisdropped
    WHERE n.nspname='aybak' AND c.relkind='r' AND NOT c.relrowsecurity LOOP
    PERFORM aybak.enable_tenant_rls(t.table_name);
  END LOOP;
END
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'integration_endpoint','inbound_message','outbox_event','sync_device','sync_change_log'
  ] LOOP
    EXECUTE format('SELECT aybak.enable_audit_trigger(%L::regclass)', 'aybak.' || t);
  END LOOP;
END
$$;

-- Model registration is partly global (tenant_id NULL = platform catalogue).
-- Replace the generic tenant-only policy with one that also exposes global rows read-only.
DROP POLICY tenant_isolation ON ai_model_registration;
CREATE POLICY tenant_isolation ON ai_model_registration
  USING (tenant_id IS NULL OR tenant_id = aybak.current_tenant_id())
  WITH CHECK (tenant_id = aybak.current_tenant_id());

CREATE TRIGGER delivery_attempt_immutable BEFORE UPDATE OR DELETE ON delivery_attempt FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();
CREATE TRIGGER ai_output_review_immutable BEFORE UPDATE OR DELETE ON ai_output_review FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();

CREATE FUNCTION aybak.block_unapproved_ai()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_ok boolean;
BEGIN
  SELECT approval_status IN ('approved','approved_with_conditions') AND human_oversight_required IS NOT FALSE
    INTO v_ok FROM aybak.ai_model_registration WHERE id = NEW.model_registration_id;
  IF v_ok IS NOT TRUE THEN
    RAISE EXCEPTION 'AI inference requires an approved, human-overseen model registration' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER ai_inference_approval_guard BEFORE INSERT ON ai_inference_record
  FOR EACH ROW EXECUTE FUNCTION aybak.block_unapproved_ai();

COMMIT;
