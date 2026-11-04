-- AYBAK Hospital Platform — encounters, scheduling, and EMR/medical history.
-- Requires V001. Run once through the migration tool.

BEGIN;
SET LOCAL search_path = aybak, public;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

CREATE TABLE encounter (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  facility_id uuid NOT NULL,
  encounter_class text NOT NULL CHECK (encounter_class IN ('ambulatory','emergency','inpatient','observation','virtual','home_health')),
  status text NOT NULL CHECK (status IN ('planned','arrived','triaged','in_progress','on_leave','completed','cancelled','entered_in_error')),
  reason_code text,
  reason_text text,
  attending_practitioner_id uuid,
  starts_at timestamptz,
  ends_at timestamptz,
  source_timezone text NOT NULL,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, id, patient_id),
  UNIQUE (tenant_id, id, facility_id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, attending_practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at >= starts_at),
  CHECK (status <> 'completed' OR ends_at IS NOT NULL)
);

CREATE INDEX encounter_patient_time_idx ON encounter (tenant_id, patient_id, starts_at DESC);
CREATE INDEX encounter_facility_status_idx ON encounter (tenant_id, facility_id, status, starts_at);
CREATE INDEX encounter_attending_idx ON encounter (tenant_id, attending_practitioner_id, status) WHERE attending_practitioner_id IS NOT NULL;

CREATE TABLE care_team_member (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  encounter_id uuid NOT NULL,
  practitioner_id uuid NOT NULL,
  role_code text NOT NULL,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);

CREATE INDEX care_team_member_practitioner_idx ON care_team_member (tenant_id, practitioner_id, valid_from, valid_until);
CREATE UNIQUE INDEX care_team_member_active_uq ON care_team_member (tenant_id, encounter_id, practitioner_id, role_code) WHERE valid_until IS NULL;

CREATE TABLE location_assignment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  encounter_id uuid NOT NULL,
  facility_id uuid NOT NULL,
  department_id uuid,
  location_code text NOT NULL,
  assignment_type text NOT NULL CHECK (assignment_type IN ('admission','transfer','temporary','discharge')),
  assigned_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_staff_id uuid NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, department_id) REFERENCES department(tenant_id, id),
  FOREIGN KEY (tenant_id, actor_staff_id) REFERENCES staff_principal(tenant_id, id)
);

CREATE INDEX location_assignment_encounter_time_idx ON location_assignment (tenant_id, encounter_id, assigned_at DESC);

CREATE TABLE schedule_resource (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  facility_id uuid NOT NULL,
  practitioner_id uuid,
  resource_type text NOT NULL CHECK (resource_type IN ('practitioner','room','bed','equipment','modality','combined')),
  code text NOT NULL,
  display_name text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, facility_id, code),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (resource_type <> 'practitioner' OR practitioner_id IS NOT NULL)
);

CREATE TABLE resource_unavailability (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  resource_id uuid NOT NULL,
  unavailable_during tstzrange NOT NULL,
  reason_code text NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, resource_id) REFERENCES schedule_resource(tenant_id, id),
  CHECK (NOT isempty(unavailable_during)),
  EXCLUDE USING gist (tenant_id WITH =, resource_id WITH =, unavailable_during WITH &&)
);

CREATE TABLE appointment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  resource_id uuid NOT NULL,
  referring_service_request_id uuid,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  source_timezone text NOT NULL,
  occupied_during tstzrange GENERATED ALWAYS AS (tstzrange(starts_at, ends_at, '[)')) STORED,
  visit_type_code text NOT NULL,
  reason_text text,
  status text NOT NULL CHECK (status IN ('proposed','requested','booked','confirmed','arrived','in_progress','completed','cancelled','no_show')),
  cancellation_reason text,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, resource_id) REFERENCES schedule_resource(tenant_id, id),
  CHECK (ends_at > starts_at),
  CHECK (status NOT IN ('cancelled','no_show') OR cancellation_reason IS NOT NULL),
  EXCLUDE USING gist (tenant_id WITH =, resource_id WITH =, occupied_during WITH &&)
    WHERE (status IN ('booked','confirmed','arrived','in_progress'))
);

CREATE INDEX appointment_patient_time_idx ON appointment (tenant_id, patient_id, starts_at DESC);
CREATE INDEX appointment_resource_status_time_idx ON appointment (tenant_id, resource_id, status, starts_at);
CREATE INDEX appointment_encounter_idx ON appointment (tenant_id, encounter_id) WHERE encounter_id IS NOT NULL;

CREATE TABLE appointment_transition (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  appointment_id uuid NOT NULL,
  from_status text,
  to_status text NOT NULL,
  base_version integer NOT NULL CHECK (base_version > 0),
  actor_staff_id uuid NOT NULL,
  reason text,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  correlation_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, appointment_id) REFERENCES appointment(tenant_id, id),
  FOREIGN KEY (tenant_id, actor_staff_id) REFERENCES staff_principal(tenant_id, id),
  CHECK (from_status IS NULL OR from_status <> to_status)
);

CREATE INDEX appointment_transition_history_idx ON appointment_transition (tenant_id, appointment_id, occurred_at);

CREATE TABLE clinical_document (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  document_type_code text NOT NULL,
  title text NOT NULL,
  current_version integer NOT NULL DEFAULT 0 CHECK (current_version >= 0),
  status text NOT NULL CHECK (status IN ('draft','final','amended','entered_in_error')),
  author_practitioner_id uuid NOT NULL,
  source_system text NOT NULL DEFAULT 'aybak',
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, author_practitioner_id) REFERENCES practitioner(tenant_id, id)
);

CREATE INDEX clinical_document_patient_time_idx ON clinical_document (tenant_id, patient_id, created_at DESC);
CREATE INDEX clinical_document_encounter_idx ON clinical_document (tenant_id, encounter_id, status);

CREATE TABLE document_version (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  document_id uuid NOT NULL,
  version_number integer NOT NULL CHECK (version_number > 0),
  content jsonb NOT NULL CHECK (jsonb_typeof(content) = 'object'),
  content_hash text NOT NULL CHECK (content_hash ~ '^[a-f0-9]{64}$'),
  status text NOT NULL CHECK (status IN ('draft','final','amendment','entered_in_error')),
  amendment_of_version_id uuid,
  change_reason text,
  authored_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  author_practitioner_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, document_id, version_number),
  FOREIGN KEY (tenant_id, document_id) REFERENCES clinical_document(tenant_id, id),
  FOREIGN KEY (tenant_id, amendment_of_version_id) REFERENCES document_version(tenant_id, id),
  FOREIGN KEY (tenant_id, author_practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (status NOT IN ('amendment','entered_in_error') OR (amendment_of_version_id IS NOT NULL AND change_reason IS NOT NULL))
);

CREATE INDEX document_version_history_idx ON document_version (tenant_id, document_id, version_number DESC);

CREATE TABLE signature (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  signer_practitioner_id uuid NOT NULL,
  signature_type text NOT NULL CHECK (signature_type IN ('author','co_signer','attesting','verifying')),
  signed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  assurance_level text NOT NULL,
  content_hash text NOT NULL CHECK (content_hash ~ '^[a-f0-9]{64}$'),
  signature_evidence jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(signature_evidence) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, document_version_id, signer_practitioner_id, signature_type),
  FOREIGN KEY (tenant_id, document_version_id) REFERENCES document_version(tenant_id, id),
  FOREIGN KEY (tenant_id, signer_practitioner_id) REFERENCES practitioner(tenant_id, id)
);

CREATE TABLE problem (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  code_system text NOT NULL,
  code_value text NOT NULL,
  code_version text,
  display_text text NOT NULL,
  clinical_status text NOT NULL CHECK (clinical_status IN ('active','recurrence','relapse','inactive','remission','resolved')),
  verification_status text NOT NULL CHECK (verification_status IN ('unconfirmed','provisional','differential','confirmed','refuted','entered_in_error')),
  severity_code text,
  onset_date date,
  abatement_date date,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  recorder_practitioner_id uuid,
  source text NOT NULL DEFAULT 'aybak',
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, recorder_practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (abatement_date IS NULL OR onset_date IS NULL OR abatement_date >= onset_date)
);

CREATE INDEX problem_active_patient_idx ON problem (tenant_id, patient_id, clinical_status, verification_status);
CREATE INDEX problem_code_idx ON problem (tenant_id, code_system, code_value);

CREATE TABLE allergy_intolerance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  substance_system text,
  substance_code text,
  substance_display text NOT NULL,
  allergy_type text NOT NULL CHECK (allergy_type IN ('allergy','intolerance')),
  category text CHECK (category IN ('food','medication','environment','biologic')),
  criticality text CHECK (criticality IN ('low','high','unable_to_assess')),
  verification_status text NOT NULL CHECK (verification_status IN ('unconfirmed','confirmed','refuted','entered_in_error')),
  clinical_status text NOT NULL CHECK (clinical_status IN ('active','inactive','resolved')),
  reactions jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(reactions) = 'array'),
  onset_at timestamptz,
  last_occurrence_at timestamptz,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  recorder_practitioner_id uuid,
  source text NOT NULL DEFAULT 'aybak',
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, recorder_practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK ((substance_system IS NULL) = (substance_code IS NULL))
);

CREATE INDEX allergy_active_patient_idx ON allergy_intolerance (tenant_id, patient_id, clinical_status, verification_status);
CREATE INDEX allergy_substance_idx ON allergy_intolerance (tenant_id, substance_system, substance_code) WHERE substance_code IS NOT NULL;

CREATE TABLE observation (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  code_system text NOT NULL,
  code_value text NOT NULL,
  code_version text,
  display_text text NOT NULL,
  status text NOT NULL CHECK (status IN ('registered','preliminary','final','amended','corrected','cancelled','entered_in_error')),
  category_code text,
  value_numeric numeric(24,8),
  value_text text,
  value_boolean boolean,
  value_code_system text,
  value_code text,
  unit_ucum text,
  reference_range jsonb CHECK (reference_range IS NULL OR jsonb_typeof(reference_range) = 'object'),
  interpretation_code text,
  effective_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  performer_practitioner_id uuid,
  source text NOT NULL DEFAULT 'aybak',
  corrected_observation_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, performer_practitioner_id) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, corrected_observation_id) REFERENCES observation(tenant_id, id),
  CHECK (num_nonnulls(value_numeric, value_text, value_boolean, value_code) = 1),
  CHECK (value_numeric IS NULL OR unit_ucum IS NOT NULL),
  CHECK ((value_code_system IS NULL) = (value_code IS NULL))
);

CREATE INDEX observation_patient_code_time_idx ON observation (tenant_id, patient_id, code_system, code_value, effective_at DESC);
CREATE INDEX observation_encounter_time_idx ON observation (tenant_id, encounter_id, effective_at DESC);

CREATE TABLE immunization (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  vaccine_system text NOT NULL,
  vaccine_code text NOT NULL,
  vaccine_display text NOT NULL,
  status text NOT NULL CHECK (status IN ('completed','entered_in_error','not_done')),
  occurrence_at timestamptz NOT NULL,
  lot_number text,
  expiration_date date,
  dose_quantity numeric(16,6) CHECK (dose_quantity > 0),
  dose_unit_ucum text,
  route_code text,
  site_code text,
  performer_practitioner_id uuid,
  source text NOT NULL DEFAULT 'aybak',
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, performer_practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK ((dose_quantity IS NULL) = (dose_unit_ucum IS NULL))
);

CREATE INDEX immunization_patient_time_idx ON immunization (tenant_id, patient_id, occurrence_at DESC);

CREATE TABLE procedure_record (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  code_system text NOT NULL,
  code_value text NOT NULL,
  display_text text NOT NULL,
  status text NOT NULL CHECK (status IN ('preparation','in_progress','completed','stopped','not_done','entered_in_error')),
  performed_start timestamptz,
  performed_end timestamptz,
  outcome_code text,
  performer_practitioner_id uuid,
  body_site_code text,
  source text NOT NULL DEFAULT 'aybak',
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, performer_practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (performed_end IS NULL OR performed_start IS NULL OR performed_end >= performed_start)
);

CREATE INDEX procedure_patient_time_idx ON procedure_record (tenant_id, patient_id, performed_start DESC);

CREATE TABLE family_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  relationship_code text NOT NULL,
  relative_display text,
  condition_system text NOT NULL,
  condition_code text NOT NULL,
  condition_display text NOT NULL,
  deceased_boolean boolean,
  onset_age_years numeric(4,1) CHECK (onset_age_years >= 0),
  verification_status text NOT NULL DEFAULT 'unconfirmed' CHECK (verification_status IN ('unconfirmed','confirmed','refuted','entered_in_error')),
  notes text,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id)
);

CREATE INDEX family_history_patient_idx ON family_history (tenant_id, patient_id, relationship_code);

CREATE TABLE social_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  category_code text NOT NULL,
  code_system text NOT NULL,
  code_value text NOT NULL,
  display_text text NOT NULL,
  status text NOT NULL CHECK (status IN ('current','former','never','unknown','entered_in_error')),
  value_text text,
  effective_from date,
  effective_until date,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  CHECK (effective_until IS NULL OR effective_from IS NULL OR effective_until >= effective_from)
);

CREATE INDEX social_history_patient_category_idx ON social_history (tenant_id, patient_id, category_code, status);

CREATE TABLE service_request (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  requester_practitioner_id uuid NOT NULL,
  service_type text NOT NULL CHECK (service_type IN ('laboratory','radiology','procedure','consultation','other')),
  code_system text NOT NULL,
  code_value text NOT NULL,
  display_text text NOT NULL,
  status text NOT NULL CHECK (status IN ('draft','active','on_hold','completed','revoked','entered_in_error')),
  intent text NOT NULL CHECK (intent IN ('proposal','order','plan')),
  priority text NOT NULL CHECK (priority IN ('routine','urgent','asap','stat')),
  reason_text text,
  authored_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, id, patient_id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, requester_practitioner_id) REFERENCES practitioner(tenant_id, id)
);

CREATE INDEX service_request_department_worklist_idx ON service_request (tenant_id, service_type, status, priority, authored_at);
CREATE INDEX service_request_patient_time_idx ON service_request (tenant_id, patient_id, authored_at DESC);

CREATE TABLE diagnostic_result (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  service_request_id uuid,
  result_type text NOT NULL CHECK (result_type IN ('laboratory','radiology','procedure','other')),
  code_system text NOT NULL,
  code_value text NOT NULL,
  display_text text NOT NULL,
  status text NOT NULL CHECK (status IN ('registered','partial','preliminary','final','amended','corrected','cancelled','entered_in_error')),
  effective_at timestamptz,
  issued_at timestamptz,
  verified_by uuid,
  verified_at timestamptz,
  source_system text NOT NULL,
  source_resource_id text,
  corrected_result_id uuid,
  content_hash text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, id, patient_id),
  UNIQUE (tenant_id, source_system, source_resource_id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, service_request_id) REFERENCES service_request(tenant_id, id),
  FOREIGN KEY (tenant_id, service_request_id, patient_id) REFERENCES service_request(tenant_id, id, patient_id),
  FOREIGN KEY (tenant_id, verified_by) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, corrected_result_id) REFERENCES diagnostic_result(tenant_id, id),
  CHECK (status NOT IN ('final','amended','corrected') OR (verified_by IS NOT NULL AND verified_at IS NOT NULL AND issued_at IS NOT NULL)),
  CHECK (status NOT IN ('amended','corrected') OR corrected_result_id IS NOT NULL)
);

CREATE INDEX diagnostic_result_patient_time_idx ON diagnostic_result (tenant_id, patient_id, result_type, issued_at DESC);
CREATE INDEX diagnostic_result_request_idx ON diagnostic_result (tenant_id, service_request_id, status);

CREATE TABLE result_value (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  diagnostic_result_id uuid NOT NULL,
  code_system text NOT NULL,
  code_value text NOT NULL,
  display_text text NOT NULL,
  value_numeric numeric(24,8),
  value_text text,
  value_boolean boolean,
  value_code text,
  unit_ucum text,
  reference_range jsonb CHECK (reference_range IS NULL OR jsonb_typeof(reference_range) = 'object'),
  interpretation_code text,
  abnormal_flag text,
  sequence integer NOT NULL DEFAULT 1 CHECK (sequence > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, diagnostic_result_id) REFERENCES diagnostic_result(tenant_id, id),
  CHECK (num_nonnulls(value_numeric, value_text, value_boolean, value_code) = 1),
  CHECK (value_numeric IS NULL OR unit_ucum IS NOT NULL)
);

CREATE INDEX result_value_result_sequence_idx ON result_value (tenant_id, diagnostic_result_id, sequence);

CREATE TABLE clinical_provenance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  resource_type text NOT NULL,
  resource_id uuid NOT NULL,
  activity_code text NOT NULL CHECK (activity_code IN ('create','revise','verify','sign','import','correct','merge','transmit')),
  agent_staff_id uuid,
  agent_practitioner_id uuid,
  source_system text NOT NULL,
  source_resource_id text,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  policy_version text,
  mapping_version text,
  details jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(details) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, agent_staff_id) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, agent_practitioner_id) REFERENCES practitioner(tenant_id, id)
);

CREATE INDEX clinical_provenance_resource_idx ON clinical_provenance (tenant_id, resource_type, resource_id, occurred_at);

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
    'encounter','care_team_member','location_assignment','schedule_resource','resource_unavailability',
    'appointment','clinical_document','problem','allergy_intolerance','observation','immunization',
    'procedure_record','family_history','social_history','service_request','diagnostic_result',
    'result_value','clinical_provenance'
  ] LOOP
    EXECUTE format('SELECT aybak.enable_audit_trigger(%L::regclass)', 'aybak.' || t);
  END LOOP;
END
$$;

CREATE TRIGGER appointment_transition_immutable BEFORE UPDATE OR DELETE ON appointment_transition FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();
CREATE TRIGGER document_version_immutable BEFORE UPDATE OR DELETE ON document_version FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();
CREATE TRIGGER signature_immutable BEFORE UPDATE OR DELETE ON signature FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();

COMMIT;
