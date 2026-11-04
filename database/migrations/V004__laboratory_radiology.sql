-- AYBAK Hospital Platform — laboratory and radiology.
-- Requires V001–V003.

BEGIN;
SET LOCAL search_path = aybak, public;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

CREATE TABLE lab_test_definition (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  code_system text NOT NULL,
  code_value text NOT NULL,
  display_text text NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  specimen_type_code text NOT NULL,
  container_code text,
  collection_instructions text,
  method_code text,
  active boolean NOT NULL DEFAULT true,
  valid_from date NOT NULL,
  valid_until date,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, code_system, code_value, version),
  CHECK (valid_until IS NULL OR valid_until >= valid_from)
);

CREATE TABLE lab_order (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  service_request_id uuid NOT NULL,
  lab_test_definition_id uuid NOT NULL,
  accession_number text NOT NULL,
  laboratory_facility_id uuid NOT NULL,
  collection_priority text NOT NULL CHECK (collection_priority IN ('routine','urgent','asap','stat')),
  fasting_required boolean,
  clinical_question text,
  status text NOT NULL CHECK (status IN ('ordered','collection_scheduled','collected','received','in_process','preliminary','final','corrected','cancelled','rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, service_request_id),
  UNIQUE (tenant_id, accession_number),
  FOREIGN KEY (tenant_id, service_request_id) REFERENCES service_request(tenant_id, id),
  FOREIGN KEY (tenant_id, lab_test_definition_id) REFERENCES lab_test_definition(tenant_id, id),
  FOREIGN KEY (tenant_id, laboratory_facility_id) REFERENCES facility(tenant_id, id)
);

CREATE INDEX lab_order_worklist_idx ON lab_order (tenant_id, laboratory_facility_id, status, collection_priority);

CREATE TABLE specimen (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  lab_order_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  specimen_identifier text NOT NULL,
  specimen_type_code text NOT NULL,
  container_code text,
  collected_at timestamptz,
  collected_by uuid,
  status text NOT NULL CHECK (status IN ('expected','collected','received','rejected','insufficient','disposed','entered_in_error')),
  rejection_reason_code text,
  recollection_of_specimen_id uuid,
  barcode_hash text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, specimen_identifier),
  FOREIGN KEY (tenant_id, lab_order_id) REFERENCES lab_order(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, collected_by) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, recollection_of_specimen_id) REFERENCES specimen(tenant_id, id),
  CHECK (status <> 'collected' OR (collected_at IS NOT NULL AND collected_by IS NOT NULL)),
  CHECK (status NOT IN ('rejected','insufficient') OR rejection_reason_code IS NOT NULL)
);

CREATE INDEX specimen_order_idx ON specimen (tenant_id, lab_order_id, status);
CREATE INDEX specimen_patient_time_idx ON specimen (tenant_id, patient_id, collected_at DESC);

CREATE TABLE specimen_event (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  specimen_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('labelled','collected','transported','received','rejected','recollected','stored','disposed')),
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_staff_id uuid NOT NULL,
  location_code text,
  reason text,
  details jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(details) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, specimen_id) REFERENCES specimen(tenant_id, id),
  FOREIGN KEY (tenant_id, actor_staff_id) REFERENCES staff_principal(tenant_id, id)
);

CREATE INDEX specimen_event_history_idx ON specimen_event (tenant_id, specimen_id, occurred_at);

CREATE TABLE reference_range (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  lab_test_definition_id uuid NOT NULL,
  component_system text NOT NULL,
  component_code text NOT NULL,
  method_code text,
  low_value numeric(24,8),
  high_value numeric(24,8),
  unit_ucum text NOT NULL,
  age_min_days integer CHECK (age_min_days >= 0),
  age_max_days integer CHECK (age_max_days >= 0),
  sex_context_code text,
  physiological_context_code text,
  range_text text,
  valid_from date NOT NULL,
  valid_until date,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, lab_test_definition_id) REFERENCES lab_test_definition(tenant_id, id),
  CHECK (low_value IS NOT NULL OR high_value IS NOT NULL OR range_text IS NOT NULL),
  CHECK (high_value IS NULL OR low_value IS NULL OR high_value >= low_value),
  CHECK (age_max_days IS NULL OR age_min_days IS NULL OR age_max_days >= age_min_days),
  CHECK (valid_until IS NULL OR valid_until >= valid_from)
);

CREATE INDEX reference_range_lookup_idx ON reference_range (tenant_id, lab_test_definition_id, component_system, component_code, method_code, valid_from);

CREATE TABLE lab_result (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  lab_order_id uuid NOT NULL,
  specimen_id uuid,
  diagnostic_result_id uuid NOT NULL,
  analyzer_identifier text,
  analyzer_flags text[],
  technical_reviewed_by uuid,
  technical_reviewed_at timestamptz,
  clinical_verified_by uuid,
  clinical_verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, diagnostic_result_id),
  FOREIGN KEY (tenant_id, lab_order_id) REFERENCES lab_order(tenant_id, id),
  FOREIGN KEY (tenant_id, specimen_id) REFERENCES specimen(tenant_id, id),
  FOREIGN KEY (tenant_id, diagnostic_result_id) REFERENCES diagnostic_result(tenant_id, id),
  FOREIGN KEY (tenant_id, technical_reviewed_by) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, clinical_verified_by) REFERENCES practitioner(tenant_id, id),
  CHECK ((technical_reviewed_at IS NULL) = (technical_reviewed_by IS NULL)),
  CHECK ((clinical_verified_at IS NULL) = (clinical_verified_by IS NULL))
);

CREATE INDEX lab_result_order_idx ON lab_result (tenant_id, lab_order_id);
CREATE INDEX lab_result_verification_idx ON lab_result (tenant_id, clinical_verified_by, clinical_verified_at);

CREATE TABLE delta_check (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  lab_result_id uuid NOT NULL,
  prior_diagnostic_result_id uuid,
  rule_version text NOT NULL,
  outcome text NOT NULL CHECK (outcome IN ('not_applicable','passed','flagged','failed')),
  details jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(details) = 'object'),
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, lab_result_id) REFERENCES lab_result(tenant_id, id),
  FOREIGN KEY (tenant_id, prior_diagnostic_result_id) REFERENCES diagnostic_result(tenant_id, id),
  FOREIGN KEY (tenant_id, reviewed_by) REFERENCES practitioner(tenant_id, id)
);

CREATE TABLE imaging_order (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  service_request_id uuid NOT NULL,
  accession_number text NOT NULL,
  modality_code text NOT NULL,
  laterality_code text,
  clinical_question text NOT NULL,
  priority text NOT NULL CHECK (priority IN ('routine','urgent','asap','stat')),
  status text NOT NULL CHECK (status IN ('ordered','protocol_review','scheduled','arrived','acquired','preliminary','final','corrected','cancelled')),
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  source_timezone text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, service_request_id),
  UNIQUE (tenant_id, accession_number),
  FOREIGN KEY (tenant_id, service_request_id) REFERENCES service_request(tenant_id, id),
  CHECK (scheduled_end IS NULL OR scheduled_start IS NULL OR scheduled_end > scheduled_start)
);

CREATE INDEX imaging_order_worklist_idx ON imaging_order (tenant_id, modality_code, status, priority, scheduled_start);

CREATE TABLE imaging_protocol (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  imaging_order_id uuid NOT NULL,
  protocol_code text NOT NULL,
  protocol_version text NOT NULL,
  screening_context jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(screening_context) = 'object'),
  missing_context text[] NOT NULL DEFAULT '{}',
  reviewed_by uuid NOT NULL,
  reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  decision text NOT NULL CHECK (decision IN ('approved','changed','rejected','needs_more_information')),
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, imaging_order_id) REFERENCES imaging_order(tenant_id, id),
  FOREIGN KEY (tenant_id, reviewed_by) REFERENCES practitioner(tenant_id, id)
);

CREATE TABLE imaging_study_ref (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  imaging_order_id uuid,
  patient_id uuid NOT NULL,
  study_instance_uid text NOT NULL,
  accession_number text,
  pacs_endpoint_ref text NOT NULL,
  study_datetime timestamptz,
  modality_code text,
  study_description text,
  series_count integer CHECK (series_count >= 0),
  instance_count integer CHECK (instance_count >= 0),
  metadata_hash text,
  status text NOT NULL CHECK (status IN ('available','partial','unavailable','entered_in_error')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, study_instance_uid),
  FOREIGN KEY (tenant_id, imaging_order_id) REFERENCES imaging_order(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id)
);

CREATE INDEX imaging_study_patient_time_idx ON imaging_study_ref (tenant_id, patient_id, study_datetime DESC);
CREATE INDEX imaging_study_order_idx ON imaging_study_ref (tenant_id, imaging_order_id);

CREATE TABLE radiology_report (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  imaging_order_id uuid NOT NULL,
  imaging_study_ref_id uuid,
  patient_id uuid NOT NULL,
  diagnostic_result_id uuid,
  current_version integer NOT NULL DEFAULT 0 CHECK (current_version >= 0),
  status text NOT NULL CHECK (status IN ('draft','preliminary','interim','final','amended','corrected','entered_in_error')),
  author_practitioner_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, imaging_order_id) REFERENCES imaging_order(tenant_id, id),
  FOREIGN KEY (tenant_id, imaging_study_ref_id) REFERENCES imaging_study_ref(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, diagnostic_result_id) REFERENCES diagnostic_result(tenant_id, id),
  FOREIGN KEY (tenant_id, author_practitioner_id) REFERENCES practitioner(tenant_id, id)
);

CREATE INDEX radiology_report_order_idx ON radiology_report (tenant_id, imaging_order_id, current_version DESC);
CREATE INDEX radiology_report_author_idx ON radiology_report (tenant_id, author_practitioner_id, status);

CREATE TABLE radiology_report_version (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  radiology_report_id uuid NOT NULL,
  version_number integer NOT NULL CHECK (version_number > 0),
  body_text text NOT NULL CHECK (length(btrim(body_text)) > 0),
  impression_text text,
  recommendation_text text,
  technique_text text,
  comparison_text text,
  status text NOT NULL CHECK (status IN ('draft','preliminary','interim','final','amended')),
  author_practitioner_id uuid NOT NULL,
  authored_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  signed_at timestamptz,
  signature_id uuid,
  amended_from_version integer,
  amendment_reason text,
  content_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, radiology_report_id, version_number),
  FOREIGN KEY (tenant_id, radiology_report_id) REFERENCES radiology_report(tenant_id, id),
  FOREIGN KEY (tenant_id, author_practitioner_id) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, signature_id) REFERENCES signature(tenant_id, id),
  CHECK (status NOT IN ('final','amended') OR (signed_at IS NOT NULL AND signature_id IS NOT NULL)),
  CHECK (version_number = 1 OR amended_from_version IS NOT NULL),
  CHECK (status <> 'amended' OR amendment_reason IS NOT NULL)
);

CREATE INDEX radiology_report_version_history_idx ON radiology_report_version (tenant_id, radiology_report_id, version_number DESC);

CREATE TABLE critical_result_notification (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  diagnostic_result_id uuid,
  radiology_report_id uuid,
  severity text NOT NULL CHECK (severity IN ('critical','urgent','unexpected')),
  notified_practitioner_id uuid NOT NULL,
  notified_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  notified_by uuid NOT NULL,
  channel text NOT NULL CHECK (channel IN ('phone','in_person','secure_message','page')),
  read_back_confirmed boolean NOT NULL,
  action_taken text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, diagnostic_result_id) REFERENCES diagnostic_result(tenant_id, id),
  FOREIGN KEY (tenant_id, radiology_report_id) REFERENCES radiology_report(tenant_id, id),
  FOREIGN KEY (tenant_id, notified_practitioner_id) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, notified_by) REFERENCES practitioner(tenant_id, id),
  CHECK (num_nonnulls(diagnostic_result_id, radiology_report_id) = 1)
);

CREATE INDEX critical_result_notification_patient_idx ON critical_result_notification (tenant_id, patient_id, notified_at DESC);

CREATE TABLE external_result_import (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  source_system text NOT NULL,
  source_resource_id text NOT NULL,
  message_control_id text NOT NULL,
  message_type text NOT NULL,
  payload_hash text NOT NULL,
  mapping_version text NOT NULL,
  imported_diagnostic_result_id uuid,
  status text NOT NULL CHECK (status IN ('received','parsed','mapped','needs_review','accepted','rejected','duplicate')),
  quarantine_reason text,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, source_system, message_control_id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, imported_diagnostic_result_id) REFERENCES diagnostic_result(tenant_id, id),
  CHECK (status NOT IN ('needs_review','rejected') OR quarantine_reason IS NOT NULL)
);

CREATE INDEX external_result_import_review_idx ON external_result_import (tenant_id, status, received_at);

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
    'lab_test_definition','lab_order','specimen','specimen_event','reference_range','lab_result',
    'delta_check','imaging_order','imaging_protocol','imaging_study_ref','radiology_report',
    'radiology_report_version','critical_result_notification','external_result_import'
  ] LOOP
    EXECUTE format('SELECT aybak.enable_audit_trigger(%L::regclass)', 'aybak.' || t);
  END LOOP;
END
$$;

CREATE TRIGGER specimen_event_immutable BEFORE UPDATE OR DELETE ON specimen_event FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();
CREATE TRIGGER radiology_report_version_immutable BEFORE UPDATE OR DELETE ON radiology_report_version FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();
CREATE TRIGGER critical_result_notification_immutable BEFORE UPDATE OR DELETE ON critical_result_notification FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();

-- Lab and imaging orders may not be accepted without a resolvable patient + request.
CREATE FUNCTION aybak.validate_lab_order()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_service text;
BEGIN
  SELECT status INTO v_service FROM aybak.service_request
   WHERE tenant_id = NEW.tenant_id AND id = NEW.service_request_id;
  IF v_service IN ('revoked','entered_in_error') THEN
    RAISE EXCEPTION 'Cannot create a laboratory order from a % service request', v_service
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER lab_order_validate BEFORE INSERT ON lab_order FOR EACH ROW EXECUTE FUNCTION aybak.validate_lab_order();

COMMIT;
