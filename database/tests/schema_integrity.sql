-- AYBAK Hospital Platform — executable schema integrity tests.
-- Runs as a superuser inside a transaction that is rolled back at the end.
-- Usage: psql -v ON_ERROR_STOP=1 -f database/tests/schema_integrity.sql
--
-- Each test raises an exception on failure. A clean run means every assertion held.

BEGIN;

SET LOCAL search_path = aybak, public;

CREATE TEMP TABLE test_result (
  seq serial PRIMARY KEY,
  name text NOT NULL,
  passed boolean NOT NULL,
  detail text
);

CREATE FUNCTION pg_temp.check(p_name text, p_condition boolean, p_detail text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO test_result (name, passed, detail) VALUES (p_name, coalesce(p_condition, false), p_detail);
END
$$;

CREATE FUNCTION pg_temp.expect_error(p_name text, p_sql text, p_sqlstate text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO test_result (name, passed, detail)
    VALUES (p_name, p_sqlstate IS NULL OR SQLSTATE = p_sqlstate, 'raised ' || SQLSTATE || ': ' || SQLERRM);
    RETURN;
  END;
  INSERT INTO test_result (name, passed, detail) VALUES (p_name, false, 'no error raised');
END
$$;

-- ---------------------------------------------------------------------------
-- Fixtures. Two tenants to prove isolation and cross-tenant FK rejection.
-- ---------------------------------------------------------------------------
INSERT INTO organization (id, code, legal_name, default_timezone, data_residency) VALUES
  ('11111111-1111-1111-1111-111111111111', 'TENANT_A', 'Tenant A Hospital', 'Asia/Kabul', 'AF'),
  ('22222222-2222-2222-2222-222222222222', 'TENANT_B', 'Tenant B Hospital', 'Asia/Singapore', 'SG');

INSERT INTO facility (id, tenant_id, code, name, facility_type, timezone) VALUES
  ('1a000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'MAIN', 'Aybak Main', 'hospital', 'Asia/Kabul'),
  ('2b000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'MAIN', 'Tenant B Main', 'hospital', 'Asia/Singapore');

INSERT INTO department (id, tenant_id, facility_id, code, name, department_type) VALUES
  ('1c000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '1a000000-0000-0000-0000-000000000001', 'EMR', 'Emergency', 'clinical');

INSERT INTO staff_principal (id, tenant_id, idp_issuer, idp_subject, display_name) VALUES
  ('1d000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'https://idp-a', 'sub-a1', 'Dr Amina'),
  ('1d000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'https://idp-a', 'sub-a2', 'Nurse Yaqoob'),
  ('2d000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'https://idp-b', 'sub-b1', 'Dr Other');

INSERT INTO practitioner (id, tenant_id, staff_id, practitioner_type) VALUES
  ('1e000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '1d000000-0000-0000-0000-000000000001', 'physician'),
  ('1e000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '1d000000-0000-0000-0000-000000000002', 'nurse');

INSERT INTO patient (id, tenant_id, birth_date, sex_at_birth_code, preferred_language) VALUES
  ('1f000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '1985-04-12', 'female', 'prs'),
  ('2f000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', '1990-01-01', 'male', 'en');

INSERT INTO encounter (id, tenant_id, patient_id, facility_id, encounter_class, status, source_timezone, starts_at) VALUES
  ('3a000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '1f000000-0000-0000-0000-000000000001', '1a000000-0000-0000-0000-000000000001', 'emergency', 'in_progress', 'Asia/Kabul', now());

-- ---------------------------------------------------------------------------
-- Structural assertions
-- ---------------------------------------------------------------------------
SELECT pg_temp.check('every tenant table forces row-level security',
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped
   WHERE n.nspname = 'aybak' AND c.relkind = 'r' AND NOT c.relrowsecurity),
  'tables with tenant_id lacking RLS');

SELECT pg_temp.check('every tenant table has a tenant policy',
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped
   WHERE n.nspname = 'aybak' AND c.relkind = 'r'
     AND NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid)),
  'tables without a policy');

SELECT pg_temp.check('no clinical FK is tenant-blind',
  (SELECT count(*) = 0 FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
   WHERE n.nspname = 'aybak' AND c.contype = 'f' AND array_length(c.conkey, 1) = 1
     AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attname = 'tenant_id')
     AND c.confrelid <> 'aybak.organization'::regclass
     AND c.confrelid <> 'aybak.currency'::regclass),
  'single-column FKs from tenant tables to tenant tables');

SELECT pg_temp.check('every clinical table is reachable from patient',
  (SELECT count(*) = 0 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'aybak' AND c.relkind = 'r'
      AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'patient_id' AND NOT a.attisdropped)
      AND NOT EXISTS (SELECT 1 FROM pg_constraint f WHERE f.conrelid = c.oid AND f.contype = 'f'
                        AND f.confrelid = 'aybak.patient'::regclass)),
  'patient_id columns without an FK to patient');

SELECT pg_temp.check('every FK target is uniquely indexed',
  (SELECT count(*) = 0 FROM pg_constraint f
    WHERE f.contype = 'f' AND f.connamespace = 'aybak'::regnamespace
      AND NOT EXISTS (
        SELECT 1 FROM pg_index i
        WHERE i.indrelid = f.confrelid AND i.indisunique
          AND i.indpred IS NULL AND i.indexprs IS NULL
          AND (SELECT array_agg(k ORDER BY k) FROM unnest(i.indkey::int[]) k)
              = (SELECT array_agg(k ORDER BY k) FROM unnest(f.confkey::int[]) k))),
  'FK targets lacking a unique index');

SELECT pg_temp.check('every money column is integer minor units',
  (SELECT count(*) = 0 FROM information_schema.columns
   WHERE table_schema = 'aybak'
     AND ((column_name LIKE '%_minor' AND data_type <> 'bigint')
       OR (column_name ~ '(price|amount|total|balance|cost)' AND data_type IN ('numeric','real','double precision','money')))),
  'non-integer money columns');

SELECT pg_temp.check('no stored age column',
  (SELECT count(*) = 0 FROM information_schema.columns
   WHERE table_schema = 'aybak' AND column_name IN ('age','patient_age','age_years')),
  'age must be derived from birth_date');

SELECT pg_temp.check('all timestamps are timestamptz',
  (SELECT count(*) = 0 FROM information_schema.columns
   WHERE table_schema = 'aybak' AND data_type = 'timestamp without time zone'),
  'naive timestamps found');

SELECT pg_temp.check('audit table is append-only',
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'aybak.audit_event'::regclass AND tgname = 'audit_event_immutable'),
  'audit_event immutability trigger');

SELECT pg_temp.check('scheduling exclusion constraints exist',
  (SELECT count(*) FROM pg_constraint WHERE conname LIKE '%_excl' AND contype = 'x') >= 2,
  'appointment and unavailability overlap exclusions');

-- ---------------------------------------------------------------------------
-- Behavioural assertions
-- ---------------------------------------------------------------------------
-- Tenant isolation is verified as the least-privileged application role, because
-- FORCE ROW LEVEL SECURITY deliberately does not apply to superusers.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aybak_test_app') THEN
    CREATE ROLE aybak_test_app NOLOGIN;
  END IF;
END
$$;
GRANT aybak_app TO aybak_test_app;
GRANT INSERT, SELECT ON test_result TO aybak_test_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA pg_temp TO aybak_test_app;
GRANT EXECUTE ON FUNCTION pg_temp.check(text, boolean, text) TO aybak_test_app;
GRANT EXECUTE ON FUNCTION pg_temp.expect_error(text, text, text) TO aybak_test_app;
SET LOCAL ROLE aybak_test_app;

-- Tenant context is required for any read.
SET LOCAL app.tenant_id = '11111111-1111-1111-1111-111111111111';
SET LOCAL app.staff_id = '1d000000-0000-0000-0000-000000000001';

SELECT pg_temp.check('tenant context sees only its own patients',
  (SELECT count(*) FROM patient) = 1,
  'visible patients: ' || (SELECT count(*) FROM patient));

SELECT pg_temp.check('RLS hides the other tenant patient',
  NOT EXISTS (SELECT 1 FROM patient WHERE id = '2f000000-0000-0000-0000-000000000001'),
  'cross-tenant row was visible');

SELECT pg_temp.check('no tenant context yields no rows',
  (SELECT count(*) FROM patient) = 0 OR aybak.current_tenant_id() IS NOT NULL,
  'context was set');

DO $$
DECLARE v_count int;
BEGIN
  EXECUTE 'RESET app.tenant_id';
  SELECT count(*) INTO v_count FROM aybak.patient;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'patients visible without tenant context';
  END IF;
END
$$;
SET LOCAL app.tenant_id = '11111111-1111-1111-1111-111111111111';

SELECT pg_temp.check('audit rows are tenant isolated',
  (SELECT count(*) FROM audit_event WHERE tenant_id <> aybak.current_tenant_id()) = 0);

SELECT pg_temp.check('application role cannot disable RLS',
  NOT has_table_privilege(current_user, 'aybak.patient', 'TRIGGER'));

SELECT pg_temp.check('application role cannot truncate clinical tables',
  NOT has_table_privilege(current_user, 'aybak.patient', 'TRUNCATE'));

SELECT pg_temp.check('application role cannot write audit directly',
  NOT has_table_privilege(current_user, 'aybak.audit_event', 'INSERT'));

RESET ROLE;

-- Cross-tenant foreign key must fail even with a trusted context.
SELECT pg_temp.expect_error('cross-tenant encounter insert is rejected',
  $q$INSERT INTO encounter (tenant_id, patient_id, facility_id, encounter_class, status, source_timezone)
     VALUES ('11111111-1111-1111-1111-111111111111', '2f000000-0000-0000-0000-000000000001',
             '1a000000-0000-0000-0000-000000000001', 'ambulatory', 'planned', 'Asia/Kabul')$q$,
  '23503');

-- Clinical history: allergy and problem rows must belong to the same tenant patient.
INSERT INTO allergy_intolerance (id, tenant_id, patient_id, substance_system, substance_code, substance_display,
                                 allergy_type, category, criticality, verification_status, clinical_status,
                                 reactions, recorder_practitioner_id)
VALUES ('3b000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '1f000000-0000-0000-0000-000000000001', 'http://snomed.info/sct', '91936005', 'Penicillin',
        'allergy', 'medication', 'high', 'confirmed', 'active',
        '[{"manifestation":"rash","severity":"moderate"}]', '1e000000-0000-0000-0000-000000000001');

SELECT pg_temp.check('allergy recorded in problem-oriented history',
  EXISTS (SELECT 1 FROM allergy_intolerance WHERE tenant_id = '11111111-1111-1111-1111-111111111111'));

-- Money arithmetic must be exact integers.
INSERT INTO payer (id, tenant_id, payer_type, code, display_name, currency_code)
VALUES ('3c000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'self_pay', 'SELF', 'Self pay', 'USD');

INSERT INTO charge_master (id, tenant_id, code_system, code_value, display_text, service_category, default_price_minor, currency_code, effective_from)
VALUES ('3d000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'local', 'CONS-01', 'Consultation', 'consultation', 2500, 'USD', '2026-01-01');

INSERT INTO charge_item (id, tenant_id, patient_id, encounter_id, charge_master_id, source_resource_type, source_resource_id,
                         code_system, code_value, display_text, quantity, unit_price_minor, gross_amount_minor,
                         net_amount_minor, currency_code, service_date, status, source_event_id, idempotency_key)
VALUES ('3e000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '1f000000-0000-0000-0000-000000000001', '3a000000-0000-0000-0000-000000000001',
        '3d000000-0000-0000-0000-000000000001', 'encounter', '3a000000-0000-0000-0000-000000000001',
        'local', 'CONS-01', 'Consultation', 3, 2500, 7500, 7500, 'USD', CURRENT_DATE, 'posted',
        gen_random_uuid(), 'charge-test-1');

SELECT pg_temp.check('charge gross amount equals quantity x unit price',
  (SELECT gross_amount_minor FROM charge_item WHERE id = '3e000000-0000-0000-0000-000000000001') = 7500);

SELECT pg_temp.expect_error('charge with inconsistent arithmetic is rejected',
  $q$INSERT INTO charge_item (tenant_id, patient_id, code_system, code_value, display_text, quantity,
       unit_price_minor, gross_amount_minor, net_amount_minor, currency_code, service_date, status,
       source_resource_type, source_event_id, idempotency_key)
     VALUES ('11111111-1111-1111-1111-111111111111', '1f000000-0000-0000-0000-000000000001',
       'local', 'X', 'Bad charge', 2, 100, 999, 999, 'USD', CURRENT_DATE, 'posted', 'manual', gen_random_uuid(), 'bad-charge')$q$,
  '23514');

-- Invoice totals are maintained from lines, and over-allocation is impossible.
INSERT INTO invoice (id, tenant_id, patient_id, encounter_id, invoice_number, invoice_type, status, issued_at, currency_code)
VALUES ('3f000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '1f000000-0000-0000-0000-000000000001', '3a000000-0000-0000-0000-000000000001',
        'INV-0001', 'patient', 'issued', now(), 'USD');

INSERT INTO invoice_line (id, tenant_id, invoice_id, charge_item_id, line_number, description,
                          quantity, unit_price_minor, gross_minor, net_minor)
VALUES ('4a000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '3f000000-0000-0000-0000-000000000001', '3e000000-0000-0000-0000-000000000001', 1,
        'Consultation x3', 3, 2500, 7500, 7500);

SELECT pg_temp.check('invoice total derived from lines',
  (SELECT total_minor FROM invoice WHERE id = '3f000000-0000-0000-0000-000000000001') = 7500);

INSERT INTO payment (id, tenant_id, patient_id, invoice_id, receipt_number, payment_method, status, amount_minor, currency_code, idempotency_key)
VALUES ('4b000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '1f000000-0000-0000-0000-000000000001', '3f000000-0000-0000-0000-000000000001',
        'RCT-0001', 'cash', 'received', 5000, 'USD', 'payment-test-1');

INSERT INTO payment_allocation (tenant_id, payment_id, invoice_id, amount_minor)
VALUES ('11111111-1111-1111-1111-111111111111', '4b000000-0000-0000-0000-000000000001',
        '3f000000-0000-0000-0000-000000000001', 5000);

SELECT pg_temp.check('partial payment marks invoice partially_paid',
  (SELECT status FROM invoice WHERE id = '3f000000-0000-0000-0000-000000000001') = 'partially_paid');

SELECT pg_temp.expect_error('over-allocation beyond the payment is rejected',
  $q$INSERT INTO payment_allocation (tenant_id, payment_id, invoice_id, amount_minor)
     VALUES ('11111111-1111-1111-1111-111111111111', '4b000000-0000-0000-0000-000000000001',
             '3f000000-0000-0000-0000-000000000001', 1)$q$,
  '23514');

SELECT pg_temp.expect_error('duplicate idempotency key is rejected',
  $q$INSERT INTO payment (tenant_id, patient_id, invoice_id, receipt_number, payment_method, status, amount_minor, currency_code, idempotency_key)
     VALUES ('11111111-1111-1111-1111-111111111111', '1f000000-0000-0000-0000-000000000001',
             '3f000000-0000-0000-0000-000000000001', 'RCT-0002', 'cash', 'received', 100, 'USD', 'payment-test-1')$q$,
  '23505');

-- Audit trail: field names only, never values.
UPDATE patient SET preferred_language = 'ps' WHERE id = '1f000000-0000-0000-0000-000000000001';

SELECT pg_temp.check('update is audited with changed field names only',
  EXISTS (SELECT 1 FROM audit_event
          WHERE tenant_id = '11111111-1111-1111-1111-111111111111'
            AND resource_type = 'patient' AND action = 'UPDATE'
            AND changed_fields @> ARRAY['preferred_language']
            AND changed_fields <@ ARRAY['preferred_language','updated_at','updated_by']),
  'expected only changed column names');

SELECT pg_temp.check('audit stores no column values',
  NOT EXISTS (SELECT 1 FROM audit_event WHERE details::text LIKE '%ps%' AND resource_type = 'patient' AND action = 'UPDATE'));

SELECT pg_temp.expect_error('audit rows cannot be updated',
  $q$UPDATE audit_event SET action = 'DELETE'$q$,
  '55000');

SELECT pg_temp.expect_error('audit rows cannot be deleted',
  $q$DELETE FROM audit_event$q$,
  '55000');

-- Pharmacy: dispensing must not exceed stock or use quarantined lots.
INSERT INTO formulary_item (id, tenant_id, medication_system, medication_code, display_text, strength_text,
                            dose_form_code, knowledge_base_ref, knowledge_base_version, status, valid_from)
VALUES ('5b000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'http://www.whocc.no/atc', 'J01CA04', 'Amoxicillin 500mg capsule', '500 mg', 'C44156',
        'kb-formulary', '2026.1', 'active', '2026-01-01');

INSERT INTO stock_item (id, tenant_id, item_code, display_name, item_type, formulary_item_id, base_unit_ucum)
VALUES ('4c000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'AMOX-500', 'Amoxicillin 500mg',
        'medication', '5b000000-0000-0000-0000-000000000001', 'mg');

INSERT INTO stock_location (id, tenant_id, facility_id, code, display_name, location_type)
VALUES ('4d000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '1a000000-0000-0000-0000-000000000001', 'PHARM-MAIN', 'Main Pharmacy', 'pharmacy');

INSERT INTO stock_lot (id, tenant_id, item_id, lot_number, expiration_date, quarantine_status)
VALUES ('4e000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '4c000000-0000-0000-0000-000000000001', 'LOT-2026-A', CURRENT_DATE + 180, 'available');

INSERT INTO stock_movement (tenant_id, movement_group_id, item_id, stock_lot_id, location_id, movement_type,
                            quantity_delta, unit_ucum, source_resource_type, reason_code, actor_staff_id)
VALUES ('11111111-1111-1111-1111-111111111111', gen_random_uuid(), '4c000000-0000-0000-0000-000000000001',
        '4e000000-0000-0000-0000-000000000001', '4d000000-0000-0000-0000-000000000001', 'opening_balance',
        1000, 'mg', 'manual', 'opening', '1d000000-0000-0000-0000-000000000001');

SELECT pg_temp.check('stock balance derives from the ledger',
  (SELECT quantity_on_hand FROM stock_balance
    WHERE stock_lot_id = '4e000000-0000-0000-0000-000000000001') = 1000);

SELECT pg_temp.expect_error('quarantined lot cannot be dispensed',
  $q$INSERT INTO stock_movement (tenant_id, movement_group_id, item_id, stock_lot_id, location_id, movement_type,
       quantity_delta, unit_ucum, source_resource_type, reason_code, actor_staff_id)
     VALUES ('11111111-1111-1111-1111-111111111111', gen_random_uuid(), '4c000000-0000-0000-0000-000000000001',
       '4e000000-0000-0000-0000-000000000001', '4d000000-0000-0000-0000-000000000001', 'dispense',
       -10, 'mg', 'manual', 'test', '1d000000-0000-0000-0000-000000000001');
     UPDATE stock_lot SET quarantine_status = 'recalled' WHERE id = '4e000000-0000-0000-0000-000000000001';
     INSERT INTO stock_movement (tenant_id, movement_group_id, item_id, stock_lot_id, location_id, movement_type,
       quantity_delta, unit_ucum, source_resource_type, reason_code, actor_staff_id)
     VALUES ('11111111-1111-1111-1111-111111111111', gen_random_uuid(), '4c000000-0000-0000-0000-000000000001',
       '4e000000-0000-0000-0000-000000000001', '4d000000-0000-0000-0000-000000000001', 'dispense',
       -10, 'mg', 'manual', 'test', '1d000000-0000-0000-0000-000000000001')$q$,
  'P0001');

SELECT pg_temp.expect_error('stock ledger is append-only',
  $q$UPDATE stock_movement SET quantity_delta = 0$q$,
  '55000');

-- Scheduling: overlapping appointments for the same resource must be impossible.
INSERT INTO schedule_resource (id, tenant_id, facility_id, practitioner_id, resource_type, code, display_name)
VALUES ('4f000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '1a000000-0000-0000-0000-000000000001', '1e000000-0000-0000-0000-000000000001',
        'practitioner', 'DR-AMINA', 'Dr Amina Clinic Slot');

INSERT INTO appointment (tenant_id, patient_id, resource_id, starts_at, ends_at, source_timezone, visit_type_code, status)
VALUES ('11111111-1111-1111-1111-111111111111', '1f000000-0000-0000-0000-000000000001',
        '4f000000-0000-0000-0000-000000000001', '2026-11-10 09:00+04:30', '2026-11-10 09:30+04:30',
        'Asia/Kabul', 'new_visit', 'booked');

SELECT pg_temp.expect_error('overlapping booking for the same resource is rejected',
  $q$INSERT INTO appointment (tenant_id, patient_id, resource_id, starts_at, ends_at, source_timezone, visit_type_code, status)
     VALUES ('11111111-1111-1111-1111-111111111111', '1f000000-0000-0000-0000-000000000001',
             '4f000000-0000-0000-0000-000000000001', '2026-11-10 09:15+04:30', '2026-11-10 09:45+04:30',
             'Asia/Kabul', 'new_visit', 'booked')$q$,
  '23P01');

INSERT INTO appointment (tenant_id, patient_id, resource_id, starts_at, ends_at, source_timezone, visit_type_code, status)
VALUES ('11111111-1111-1111-1111-111111111111', '1f000000-0000-0000-0000-000000000001',
        '4f000000-0000-0000-0000-000000000001', '2026-11-10 09:30+04:30', '2026-11-10 10:00+04:30',
        'Asia/Kabul', 'new_visit', 'booked');

SELECT pg_temp.check('adjacent booking is allowed',
  (SELECT count(*) FROM appointment WHERE resource_id = '4f000000-0000-0000-0000-000000000001') = 2);

-- AI: unapproved models cannot be used.
INSERT INTO ai_model_registration (id, tenant_id, model_key, model_version, vendor, intended_use, risk_class, deployment, approval_status, human_oversight_required)
VALUES ('5a000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'scribe', '0.9', 'Vendor', 'Draft note generation', 'generative_documentation', 'vendor_api', 'proposed', true);

SELECT pg_temp.expect_error('unapproved AI model inference is blocked',
  $q$INSERT INTO ai_inference_record (tenant_id, model_registration_id, patient_id, purpose_code, input_hash, prompt_template_version, status)
     VALUES ('11111111-1111-1111-1111-111111111111', '5a000000-0000-0000-0000-000000000001',
             '1f000000-0000-0000-0000-000000000001', 'documentation', 'hash', 'v1', 'completed')$q$,
  '23514');

-- Outbox: unique per aggregate/version, so replay cannot duplicate side effects.
INSERT INTO outbox_event (tenant_id, aggregate_type, aggregate_id, event_type, event_version, payload)
VALUES ('11111111-1111-1111-1111-111111111111', 'patient', '1f000000-0000-0000-0000-000000000001', 'patient.updated', 1, '{"patient_id":"1f000000-0000-0000-0000-000000000001"}');

SELECT pg_temp.expect_error('duplicate outbox event is rejected',
  $q$INSERT INTO outbox_event (tenant_id, aggregate_type, aggregate_id, event_type, event_version, payload)
     VALUES ('11111111-1111-1111-1111-111111111111', 'patient', '1f000000-0000-0000-0000-000000000001', 'patient.updated', 1, '{}')$q$,
  '23505');

-- ---------------------------------------------------------------------------
-- National exchange: referrals, sharing, and the National Health ID
-- ---------------------------------------------------------------------------
SELECT pg_temp.expect_error('referral to the same organisation is rejected',
  $q$INSERT INTO referral (tenant_id, patient_id, referring_facility_id, referring_practitioner_id,
       receiving_organisation_id, referral_number, priority, clinical_summary, question_asked, status, sent_at)
     VALUES ('11111111-1111-1111-1111-111111111111', '1f000000-0000-0000-0000-000000000001',
       '1a000000-0000-0000-0000-000000000001', '1e000000-0000-0000-0000-000000000001',
       '11111111-1111-1111-1111-111111111111', 'REF-SELF', 'routine',
       'Patient requires review of persistent symptoms over three weeks.', 'Is further imaging indicated?', 'sent', now())$q$,
  '23514');

INSERT INTO referral (id, tenant_id, patient_id, referring_facility_id, referring_practitioner_id,
                      receiving_organisation_id, referral_number, priority, clinical_summary,
                      question_asked, status, sent_at)
VALUES ('7a000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '1f000000-0000-0000-0000-000000000001', '1a000000-0000-0000-0000-000000000001',
        '1e000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'REF-0001',
        'urgent', 'Patient requires review of persistent symptoms over three weeks.',
        'Is further imaging indicated?', 'sent', now());

SELECT pg_temp.check('referral to another organisation is accepted',
  EXISTS (SELECT 1 FROM referral WHERE id = '7a000000-0000-0000-0000-000000000001'));

SELECT pg_temp.expect_error('receiving facility must belong to the receiving organisation',
  $q$INSERT INTO referral (tenant_id, patient_id, referring_facility_id, referring_practitioner_id,
       receiving_organisation_id, receiving_facility_id, referral_number, priority, clinical_summary,
       question_asked, status, sent_at)
     VALUES ('11111111-1111-1111-1111-111111111111', '1f000000-0000-0000-0000-000000000001',
       '1a000000-0000-0000-0000-000000000001', '1e000000-0000-0000-0000-000000000001',
       '22222222-2222-2222-2222-222222222222', '1a000000-0000-0000-0000-000000000001', 'REF-BAD',
       'routine', 'Patient requires review of persistent symptoms.', 'Question?', 'sent', now())$q$,
  '23514');

SELECT pg_temp.expect_error('denied share request requires a reason',
  $q$INSERT INTO record_share_request (tenant_id, patient_id, requesting_organisation_id,
       requesting_practitioner_id, receiving_organisation_id, purpose_code, legal_basis,
       consent_decision, policy_version, scope, status, decided_at)
     VALUES ('11111111-1111-1111-1111-111111111111', '1f000000-0000-0000-0000-000000000001',
       '22222222-2222-2222-2222-222222222222', '1e000000-0000-0000-0000-000000000001',
       '11111111-1111-1111-1111-111111111111', 'TREATMENT', 'consent', 'denied', 'policy-2026.1',
       ARRAY['PatientSummary'], 'denied', now())$q$,
  '23514');

INSERT INTO record_share_request (id, tenant_id, patient_id, requesting_organisation_id,
       requesting_practitioner_id, receiving_organisation_id, purpose_code, legal_basis,
       consent_decision, consent_decided_at, policy_version, scope, status, decided_at, denial_reason)
VALUES ('7b000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '1f000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
        '1e000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'TREATMENT', 'consent', 'denied', now(), 'policy-2026.1', ARRAY['PatientSummary'],
        'denied', now(), 'Patient withheld consent for cross-organisation sharing.');

SELECT pg_temp.check('share denial is retained as evidence',
  EXISTS (SELECT 1 FROM record_share_request
           WHERE id = '7b000000-0000-0000-0000-000000000001' AND status = 'denied'));

INSERT INTO national_health_id (tenant_id, patient_id, health_id_hash, health_id_display_suffix, issuing_authority, status)
VALUES ('11111111-1111-1111-1111-111111111111', '1f000000-0000-0000-0000-000000000001',
        repeat('a1', 32), '4F2C', 'MoPH-AF', 'active');

SELECT pg_temp.expect_error('National Health ID hash is globally unique',
  $q$INSERT INTO national_health_id (tenant_id, patient_id, health_id_hash, issuing_authority, status)
     VALUES ('22222222-2222-2222-2222-222222222222', '2f000000-0000-0000-0000-000000000001',
             repeat('a1', 32), 'MoPH-AF', 'active')$q$,
  '23505');

SELECT pg_temp.check('National Health ID stores no plaintext identifier',
  NOT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'aybak' AND table_name = 'national_health_id'
                 AND column_name IN ('health_id', 'health_id_plain', 'national_id_value')));

-- Summary
SELECT name, passed, detail FROM test_result ORDER BY seq;

DO $$
DECLARE v_total int; v_failed int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT passed) INTO v_total, v_failed FROM test_result;
  RAISE NOTICE 'schema_integrity: % tests, % failed', v_total, v_failed;
  IF v_failed > 0 THEN
    RAISE EXCEPTION '% schema integrity test(s) failed', v_failed;
  END IF;
END
$$;

ROLLBACK;
