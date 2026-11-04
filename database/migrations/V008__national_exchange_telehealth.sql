-- AYBAK Hospital Platform — national extension: telemedicine, referrals, and
-- cross-hospital record sharing.
-- Requires V001–V007. These tables are what make the "national EHR" claims
-- testable: without them, cross-organisation sharing has no governed record.

BEGIN;
SET LOCAL search_path = aybak, public;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- Telemedicine
-- ---------------------------------------------------------------------------
CREATE TABLE telehealth_session (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  encounter_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  clinician_practitioner_id uuid NOT NULL,
  channel text NOT NULL CHECK (channel IN ('video','audio','secure_message','asynchronous_review')),
  platform_reference text,
  scheduled_start timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  patient_location_country char(2),
  patient_location_region text,
  clinician_location_facility_id uuid,
  consent_directive_id uuid,
  recording_consented boolean NOT NULL DEFAULT false,
  recording_object_id uuid,
  interpreter_required boolean NOT NULL DEFAULT false,
  interpreter_language text,
  technical_quality text CHECK (technical_quality IN ('good','degraded','failed')),
  interruption_reason text,
  status text NOT NULL CHECK (status IN ('scheduled','waiting','in_progress','completed','failed','cancelled','entered_in_error')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, encounter_id, channel, scheduled_start),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, clinician_practitioner_id) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, clinician_location_facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, consent_directive_id) REFERENCES consent_directive(tenant_id, id),
  CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at),
  CHECK (status <> 'completed' OR (started_at IS NOT NULL AND ended_at IS NOT NULL)),
  CHECK (recording_consented OR recording_object_id IS NULL),
  CHECK (NOT interpreter_required OR interpreter_language IS NOT NULL)
);

COMMENT ON TABLE telehealth_session IS 'Remote care session. A session is always attached to an encounter, so telemedicine inherits the same clinical and audit guarantees as in-person care.';

CREATE INDEX telehealth_session_clinician_idx ON telehealth_session (tenant_id, clinician_practitioner_id, scheduled_start DESC);
CREATE INDEX telehealth_session_active_idx ON telehealth_session (tenant_id, status, scheduled_start) WHERE status IN ('scheduled','waiting','in_progress');
CREATE INDEX telehealth_session_patient_idx ON telehealth_session (tenant_id, patient_id, scheduled_start DESC);

-- ---------------------------------------------------------------------------
-- Referrals between organisations
-- ---------------------------------------------------------------------------
CREATE TABLE referral (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  referring_facility_id uuid NOT NULL,
  referring_practitioner_id uuid NOT NULL,
  receiving_organisation_id uuid NOT NULL,
  receiving_facility_id uuid,
  receiving_practitioner_id uuid,
  service_request_id uuid,
  referral_number text NOT NULL,
  priority text NOT NULL CHECK (priority IN ('routine','urgent','emergency')),
  clinical_summary text NOT NULL CHECK (length(btrim(clinical_summary)) >= 20),
  question_asked text NOT NULL,
  requested_service_code text,
  status text NOT NULL CHECK (status IN ('draft','sent','acknowledged','accepted','declined','scheduled','seen','closed','cancelled','entered_in_error')),
  sent_at timestamptz,
  acknowledged_at timestamptz,
  decided_at timestamptz,
  decision_reason text,
  closed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, referral_number),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, referring_facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, referring_practitioner_id) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (receiving_organisation_id) REFERENCES organization(id),
  FOREIGN KEY (tenant_id, receiving_facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, receiving_practitioner_id) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, service_request_id) REFERENCES service_request(tenant_id, id),
  CHECK (receiving_organisation_id <> tenant_id),
  CHECK (status IN ('draft', 'entered_in_error') OR sent_at IS NOT NULL),
  CHECK (status NOT IN ('declined','cancelled') OR decision_reason IS NOT NULL)
);

COMMENT ON TABLE referral IS 'Cross-organisation referral. The receiving organisation is a different tenant; content travels through the exchange gateway, never through a cross-tenant foreign key.';

CREATE INDEX referral_receiving_idx ON referral (tenant_id, receiving_organisation_id, status, sent_at DESC);
CREATE INDEX referral_patient_idx ON referral (tenant_id, patient_id, created_at DESC);
CREATE INDEX referral_open_idx ON referral (tenant_id, status, priority) WHERE status IN ('sent','acknowledged','accepted','scheduled');

-- ---------------------------------------------------------------------------
-- Cross-hospital record sharing (national exchange)
-- ---------------------------------------------------------------------------
CREATE TABLE sharing_agreement (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  counterpart_organisation_id uuid NOT NULL,
  counterpart_country char(2) NOT NULL,
  agreement_reference text NOT NULL,
  purpose_codes text[] NOT NULL CHECK (array_length(purpose_codes, 1) >= 1),
  data_categories text[] NOT NULL CHECK (array_length(data_categories, 1) >= 1),
  direction text NOT NULL CHECK (direction IN ('inbound','outbound','bidirectional')),
  legal_basis text NOT NULL,
  effective_from date NOT NULL,
  effective_until date,
  status text NOT NULL CHECK (status IN ('draft','active','suspended','terminated')),
  signed_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, counterpart_organisation_id, agreement_reference),
  FOREIGN KEY (counterpart_organisation_id) REFERENCES organization(id),
  FOREIGN KEY (tenant_id, signed_by) REFERENCES staff_principal(tenant_id, id),
  CHECK (effective_until IS NULL OR effective_until >= effective_from)
);

CREATE INDEX sharing_agreement_active_idx ON sharing_agreement (tenant_id, status, effective_from) WHERE status = 'active';

CREATE TABLE record_share_request (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  requesting_organisation_id uuid NOT NULL,
  requesting_facility_id uuid,
  requesting_practitioner_id uuid NOT NULL,
  receiving_organisation_id uuid NOT NULL,
  purpose_code text NOT NULL,
  legal_basis text NOT NULL,
  sharing_agreement_id uuid,
  consent_decision text NOT NULL CHECK (consent_decision IN ('granted','denied','not_required','break_glass')),
  consent_decided_at timestamptz,
  policy_version text NOT NULL,
  scope text[] NOT NULL CHECK (array_length(scope, 1) >= 1),
  status text NOT NULL CHECK (status IN ('requested','approved','denied','failed','cancelled')),
  decided_at timestamptz,
  denial_reason text,
  response_reference text,
  response_hash text,
  correlation_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (requesting_organisation_id) REFERENCES organization(id),
  FOREIGN KEY (tenant_id, requesting_facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, requesting_practitioner_id) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (receiving_organisation_id) REFERENCES organization(id),
  FOREIGN KEY (tenant_id, sharing_agreement_id) REFERENCES sharing_agreement(tenant_id, id),
  CHECK (status <> 'denied' OR denial_reason IS NOT NULL),
  CHECK (status <> 'approved' OR decided_at IS NOT NULL)
);

COMMENT ON TABLE record_share_request IS 'One governed cross-organisation access decision. Denials are recorded as evidence, not discarded.';

CREATE INDEX record_share_request_patient_idx ON record_share_request (tenant_id, patient_id, created_at DESC);
CREATE INDEX record_share_request_status_idx ON record_share_request (tenant_id, requesting_organisation_id, status, created_at);

CREATE TABLE record_share_result (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  record_share_request_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  resource_type text NOT NULL,
  resource_id uuid,
  source_organisation_id uuid NOT NULL,
  source_facility_id uuid,
  effective_at timestamptz,
  content_hash text NOT NULL,
  object_storage_reference text,
  signature_verified boolean,
  provenance_verified boolean,
  status text NOT NULL CHECK (status IN ('received','verified','rejected','withdrawn')),
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, record_share_request_id, resource_type, content_hash),
  FOREIGN KEY (tenant_id, record_share_request_id) REFERENCES record_share_request(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (source_organisation_id) REFERENCES organization(id),
  FOREIGN KEY (tenant_id, source_facility_id) REFERENCES facility(tenant_id, id),
  CHECK (status <> 'rejected' OR rejection_reason IS NOT NULL)
);

COMMENT ON TABLE record_share_result IS 'Materialised artefact of an approved share, verified for signature and provenance before it can influence care.';

CREATE INDEX record_share_result_patient_idx ON record_share_result (tenant_id, patient_id, effective_at DESC);

CREATE TABLE record_locator_entry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  source_organisation_id uuid NOT NULL,
  source_facility_id uuid,
  resource_type text NOT NULL CHECK (resource_type IN ('encounter','document','result','medication','immunization','allergy','problem','imaging_report')),
  resource_count integer NOT NULL CHECK (resource_count > 0),
  first_at timestamptz NOT NULL,
  last_at timestamptz NOT NULL,
  availability text NOT NULL CHECK (availability IN ('available','restricted','destroyed','unknown')),
  last_indexed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, patient_id, source_organisation_id, resource_type, first_at),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (source_organisation_id) REFERENCES organization(id),
  FOREIGN KEY (tenant_id, source_facility_id) REFERENCES facility(tenant_id, id),
  CHECK (last_at >= first_at)
);

COMMENT ON TABLE record_locator_entry IS 'Record locator: answers "where does this patient have records" without centralising the records themselves (data sovereignty).';

CREATE INDEX record_locator_patient_idx ON record_locator_entry (tenant_id, patient_id, last_at DESC);

CREATE TABLE patient_link_organisation (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  external_organisation_id uuid NOT NULL,
  external_patient_reference text NOT NULL,
  match_basis text NOT NULL CHECK (match_basis IN ('national_health_id','verified_identifier','demographic_match','manual_review')),
  confidence numeric(5,4) CHECK (confidence > 0 AND confidence <= 1),
  verified_by uuid,
  verified_at timestamptz,
  status text NOT NULL CHECK (status IN ('proposed','confirmed','rejected','revoked')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, external_organisation_id, external_patient_reference),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (external_organisation_id) REFERENCES organization(id),
  FOREIGN KEY (tenant_id, verified_by) REFERENCES staff_principal(tenant_id, id),
  CHECK (match_basis IN ('national_health_id','manual_review') OR confidence IS NOT NULL),
  CHECK (status <> 'confirmed' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL))
);

COMMENT ON TABLE patient_link_organisation IS 'Foreign-key-free link from a local patient to a patient at another organisation. This is the only permitted cross-tenant patient reference.';

CREATE INDEX patient_link_organisation_external_idx ON patient_link_organisation (tenant_id, external_organisation_id, status);

CREATE TABLE national_health_id (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  health_id_hash text NOT NULL,
  health_id_display_suffix char(4),
  issuing_authority text NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz,
  status text NOT NULL CHECK (status IN ('proposed','active','suspended','revoked','superseded')),
  revocation_reason text,
  superseded_by_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (health_id_hash),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, superseded_by_id) REFERENCES national_health_id(tenant_id, id),
  CHECK (status <> 'revoked' OR revocation_reason IS NOT NULL),
  CHECK (expires_at IS NULL OR expires_at > issued_at),
  CHECK (superseded_by_id IS NULL OR superseded_by_id <> id)
);

COMMENT ON TABLE national_health_id IS 'National Health ID. Only a salted hash plus a display suffix is stored; the identifier is never the authentication secret and never encodes PHI.';

CREATE INDEX national_health_id_patient_idx ON national_health_id (tenant_id, patient_id, status);

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
    'telehealth_session','referral','sharing_agreement','record_share_request',
    'record_share_result','record_locator_entry','patient_link_organisation','national_health_id'
  ] LOOP
    EXECUTE format('SELECT aybak.enable_audit_trigger(%L::regclass)', 'aybak.' || t);
  END LOOP;
END
$$;

GRANT SELECT, INSERT, UPDATE, DELETE ON
  aybak.telehealth_session, aybak.referral, aybak.sharing_agreement,
  aybak.record_share_request, aybak.record_share_result,
  aybak.record_locator_entry, aybak.patient_link_organisation, aybak.national_health_id
TO aybak_app;
GRANT SELECT ON
  aybak.telehealth_session, aybak.referral, aybak.sharing_agreement,
  aybak.record_share_request, aybak.record_share_result,
  aybak.record_locator_entry, aybak.patient_link_organisation, aybak.national_health_id
TO aybak_readonly;

-- A referral must target a different organisation, and a share request may not
-- silently target the tenant itself.
CREATE FUNCTION aybak.validate_referral_target()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.receiving_organisation_id = NEW.tenant_id THEN
    RAISE EXCEPTION 'Referral must target a different organisation' USING ERRCODE = '23514';
  END IF;
  IF NEW.receiving_facility_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM aybak.facility
     WHERE id = NEW.receiving_facility_id AND tenant_id = NEW.receiving_organisation_id
  ) THEN
    RAISE EXCEPTION 'Receiving facility does not belong to the receiving organisation' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER referral_target_validate BEFORE INSERT OR UPDATE ON referral
  FOR EACH ROW EXECUTE FUNCTION aybak.validate_referral_target();

COMMIT;
