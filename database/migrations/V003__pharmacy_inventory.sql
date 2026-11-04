-- AYBAK Hospital Platform — pharmacy and inventory.
-- Requires V001–V002.

BEGIN;
SET LOCAL search_path = aybak, public;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

CREATE TABLE formulary_item (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  medication_system text NOT NULL,
  medication_code text NOT NULL,
  medication_version text,
  display_text text NOT NULL,
  ingredient_codes jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(ingredient_codes) = 'array'),
  strength_text text,
  dose_form_code text,
  knowledge_base_ref text NOT NULL,
  knowledge_base_version text NOT NULL,
  status text NOT NULL CHECK (status IN ('active','restricted','inactive','entered_in_error')),
  restriction_policy jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(restriction_policy) = 'object'),
  valid_from date NOT NULL,
  valid_until date,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, medication_system, medication_code, knowledge_base_version, valid_from),
  CHECK (valid_until IS NULL OR valid_until >= valid_from)
);

CREATE INDEX formulary_item_lookup_idx ON formulary_item (tenant_id, status, medication_system, medication_code);

CREATE TABLE medication_request (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid NOT NULL,
  prescriber_practitioner_id uuid NOT NULL,
  formulary_item_id uuid NOT NULL,
  status text NOT NULL CHECK (status IN ('draft','proposed','pending_verification','needs_changes','verified','rejected','dispensed','partially_administered','completed','cancelled','discontinued','entered_in_error')),
  dose_quantity numeric(20,6) NOT NULL CHECK (dose_quantity > 0),
  dose_unit_ucum text NOT NULL,
  route_code text NOT NULL,
  frequency_per_day numeric(8,3) CHECK (frequency_per_day > 0),
  interval_hours numeric(8,3) CHECK (interval_hours > 0),
  timing_instruction text,
  duration_days numeric(8,2) CHECK (duration_days > 0),
  indication_text text NOT NULL,
  patient_instruction text,
  authored_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  valid_from timestamptz,
  valid_until timestamptz,
  priority text NOT NULL DEFAULT 'routine' CHECK (priority IN ('routine','urgent','asap','stat')),
  pharmacy_note text,
  discontinuation_reason text,
  discontinued_by uuid,
  discontinued_at timestamptz,
  replaces_medication_request_id uuid,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, id, patient_id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, prescriber_practitioner_id) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, formulary_item_id) REFERENCES formulary_item(tenant_id, id),
  FOREIGN KEY (tenant_id, discontinued_by) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, replaces_medication_request_id) REFERENCES medication_request(tenant_id, id),
  CHECK (num_nonnulls(frequency_per_day, interval_hours, timing_instruction) >= 1),
  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from),
  CHECK (status <> 'discontinued' OR (discontinuation_reason IS NOT NULL AND discontinued_by IS NOT NULL AND discontinued_at IS NOT NULL))
);

COMMENT ON TABLE medication_request IS 'Structured proposed medication order. Safety review, pharmacist verification, dispensing, and administration are separate records.';

CREATE INDEX medication_request_patient_status_idx ON medication_request (tenant_id, patient_id, status, authored_at DESC);
CREATE INDEX medication_request_pharmacy_worklist_idx ON medication_request (tenant_id, status, priority, authored_at);
CREATE INDEX medication_request_prescriber_idx ON medication_request (tenant_id, prescriber_practitioner_id, authored_at DESC);

CREATE TABLE medication_safety_review (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  medication_request_id uuid NOT NULL,
  request_version integer NOT NULL CHECK (request_version > 0),
  review_type text NOT NULL CHECK (review_type IN ('automated','pharmacist','second_review')),
  outcome text NOT NULL CHECK (outcome IN ('passed','review_required','hard_stop','overridden','failed_closed')),
  knowledge_base_version text NOT NULL,
  input_context jsonb NOT NULL CHECK (jsonb_typeof(input_context) = 'object'),
  findings jsonb NOT NULL CHECK (jsonb_typeof(findings) = 'array'),
  missing_context text[] NOT NULL DEFAULT '{}',
  reviewer_practitioner_id uuid,
  reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, medication_request_id, request_version, review_type, id),
  FOREIGN KEY (tenant_id, medication_request_id) REFERENCES medication_request(tenant_id, id),
  FOREIGN KEY (tenant_id, reviewer_practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (review_type = 'automated' OR reviewer_practitioner_id IS NOT NULL)
);

CREATE INDEX medication_safety_review_request_idx ON medication_safety_review (tenant_id, medication_request_id, reviewed_at DESC);
CREATE INDEX medication_safety_review_alert_idx ON medication_safety_review (tenant_id, outcome, reviewed_at) WHERE outcome IN ('hard_stop','overridden','failed_closed');

CREATE TABLE medication_override (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  safety_review_id uuid NOT NULL,
  overridden_by uuid NOT NULL,
  reason_code text NOT NULL,
  reason_text text NOT NULL CHECK (length(btrim(reason_text)) >= 10),
  second_reviewer_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, safety_review_id) REFERENCES medication_safety_review(tenant_id, id),
  FOREIGN KEY (tenant_id, overridden_by) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, second_reviewer_id) REFERENCES practitioner(tenant_id, id),
  CHECK (second_reviewer_id IS NULL OR second_reviewer_id <> overridden_by)
);

CREATE TABLE stock_item (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  item_code text NOT NULL,
  display_name text NOT NULL,
  item_type text NOT NULL CHECK (item_type IN ('medication','consumable','implant','equipment','other')),
  formulary_item_id uuid,
  base_unit_ucum text NOT NULL,
  lot_tracked boolean NOT NULL DEFAULT true,
  expiry_tracked boolean NOT NULL DEFAULT true,
  controlled_item boolean NOT NULL DEFAULT false,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, item_code),
  FOREIGN KEY (tenant_id, formulary_item_id) REFERENCES formulary_item(tenant_id, id),
  CHECK (item_type <> 'medication' OR formulary_item_id IS NOT NULL)
);

CREATE TABLE stock_location (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  facility_id uuid NOT NULL,
  parent_location_id uuid,
  code text NOT NULL,
  display_name text NOT NULL,
  location_type text NOT NULL CHECK (location_type IN ('warehouse','pharmacy','ward','theater','refrigerator','quarantine','other')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, facility_id, code),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  FOREIGN KEY (tenant_id, parent_location_id) REFERENCES stock_location(tenant_id, id)
);

CREATE TABLE stock_lot (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  item_id uuid NOT NULL,
  lot_number text NOT NULL,
  serial_number text,
  expiration_date date,
  quarantine_status text NOT NULL DEFAULT 'available' CHECK (quarantine_status IN ('available','quarantined','recalled','expired','destroyed')),
  supplier_reference text,
  received_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, id, item_id),
  UNIQUE (tenant_id, item_id, lot_number, serial_number),
  FOREIGN KEY (tenant_id, item_id) REFERENCES stock_item(tenant_id, id)
);

CREATE INDEX stock_lot_fefo_idx ON stock_lot (tenant_id, item_id, quarantine_status, expiration_date, received_at);
CREATE INDEX stock_lot_number_idx ON stock_lot (tenant_id, lot_number);

CREATE TABLE stock_recall (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  item_id uuid,
  lot_id uuid,
  recall_reference text NOT NULL,
  reason text NOT NULL,
  status text NOT NULL CHECK (status IN ('announced','quarantined','completed','cancelled')),
  announced_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, item_id) REFERENCES stock_item(tenant_id, id),
  FOREIGN KEY (tenant_id, lot_id) REFERENCES stock_lot(tenant_id, id),
  CHECK (item_id IS NOT NULL OR lot_id IS NOT NULL),
  CHECK (status <> 'completed' OR completed_at IS NOT NULL)
);

CREATE TABLE dispense (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  medication_request_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  stock_lot_id uuid NOT NULL,
  stock_location_id uuid NOT NULL,
  quantity numeric(20,6) NOT NULL CHECK (quantity > 0),
  unit_ucum text NOT NULL,
  dispensed_by uuid NOT NULL,
  dispensed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  status text NOT NULL CHECK (status IN ('dispensed','partially_returned','returned','wasted','entered_in_error')),
  reversal_of_dispense_id uuid,
  idempotency_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, idempotency_key),
  FOREIGN KEY (tenant_id, medication_request_id) REFERENCES medication_request(tenant_id, id),
  FOREIGN KEY (tenant_id, medication_request_id, patient_id) REFERENCES medication_request(tenant_id, id, patient_id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, stock_lot_id) REFERENCES stock_lot(tenant_id, id),
  FOREIGN KEY (tenant_id, stock_location_id) REFERENCES stock_location(tenant_id, id),
  FOREIGN KEY (tenant_id, dispensed_by) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, reversal_of_dispense_id) REFERENCES dispense(tenant_id, id)
);

CREATE INDEX dispense_request_time_idx ON dispense (tenant_id, medication_request_id, dispensed_at DESC);
CREATE INDEX dispense_lot_time_idx ON dispense (tenant_id, stock_lot_id, dispensed_at DESC);
CREATE INDEX dispense_patient_time_idx ON dispense (tenant_id, patient_id, dispensed_at DESC);

CREATE TABLE medication_administration (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  medication_request_id uuid NOT NULL,
  dispense_id uuid,
  patient_id uuid NOT NULL,
  administrator_practitioner_id uuid NOT NULL,
  administered_at timestamptz,
  status text NOT NULL CHECK (status IN ('completed','not_done','on_hold','stopped','entered_in_error')),
  dose_quantity numeric(20,6) CHECK (dose_quantity > 0),
  dose_unit_ucum text,
  route_code text,
  reason_not_done_code text,
  witness_practitioner_id uuid,
  barcode_verification jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(barcode_verification) = 'object'),
  note text,
  idempotency_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, idempotency_key),
  FOREIGN KEY (tenant_id, medication_request_id) REFERENCES medication_request(tenant_id, id),
  FOREIGN KEY (tenant_id, medication_request_id, patient_id) REFERENCES medication_request(tenant_id, id, patient_id),
  FOREIGN KEY (tenant_id, dispense_id) REFERENCES dispense(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, administrator_practitioner_id) REFERENCES practitioner(tenant_id, id),
  FOREIGN KEY (tenant_id, witness_practitioner_id) REFERENCES practitioner(tenant_id, id),
  CHECK (status <> 'completed' OR (administered_at IS NOT NULL AND dose_quantity IS NOT NULL AND dose_unit_ucum IS NOT NULL AND route_code IS NOT NULL)),
  CHECK (status <> 'not_done' OR reason_not_done_code IS NOT NULL),
  CHECK (witness_practitioner_id IS NULL OR witness_practitioner_id <> administrator_practitioner_id)
);

CREATE INDEX medication_administration_request_time_idx ON medication_administration (tenant_id, medication_request_id, administered_at DESC);
CREATE INDEX medication_administration_patient_time_idx ON medication_administration (tenant_id, patient_id, administered_at DESC);

CREATE TABLE medication_reconciliation (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid NOT NULL,
  reconciliation_type text NOT NULL CHECK (reconciliation_type IN ('admission','transfer','discharge','outpatient')),
  source_medications jsonb NOT NULL CHECK (jsonb_typeof(source_medications) = 'array'),
  resolutions jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(resolutions) = 'array'),
  status text NOT NULL CHECK (status IN ('draft','completed','entered_in_error')),
  reconciled_by uuid,
  reconciled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, reconciled_by) REFERENCES practitioner(tenant_id, id),
  CHECK (status <> 'completed' OR (reconciled_by IS NOT NULL AND reconciled_at IS NOT NULL))
);

CREATE INDEX medication_reconciliation_patient_idx ON medication_reconciliation (tenant_id, patient_id, encounter_id, status);

CREATE TABLE stock_movement (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  movement_group_id uuid NOT NULL,
  item_id uuid NOT NULL,
  stock_lot_id uuid,
  location_id uuid NOT NULL,
  movement_type text NOT NULL CHECK (movement_type IN ('opening_balance','receipt','issue','dispense','return','waste','transfer_out','transfer_in','adjustment','destruction')),
  quantity_delta numeric(20,6) NOT NULL CHECK (quantity_delta <> 0),
  unit_ucum text NOT NULL,
  source_resource_type text NOT NULL,
  source_resource_id uuid,
  source_event_id uuid,
  reason_code text NOT NULL,
  reason_text text,
  actor_staff_id uuid NOT NULL,
  witness_staff_id uuid,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, item_id) REFERENCES stock_item(tenant_id, id),
  FOREIGN KEY (tenant_id, stock_lot_id) REFERENCES stock_lot(tenant_id, id),
  FOREIGN KEY (tenant_id, stock_lot_id, item_id) REFERENCES stock_lot(tenant_id, id, item_id),
  FOREIGN KEY (tenant_id, location_id) REFERENCES stock_location(tenant_id, id),
  FOREIGN KEY (tenant_id, actor_staff_id) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, witness_staff_id) REFERENCES staff_principal(tenant_id, id),
  CHECK ((movement_type IN ('opening_balance','receipt','return','transfer_in') AND quantity_delta > 0)
      OR (movement_type IN ('issue','dispense','waste','transfer_out','destruction') AND quantity_delta < 0)
      OR movement_type = 'adjustment'),
  CHECK (witness_staff_id IS NULL OR witness_staff_id <> actor_staff_id)
);

COMMENT ON TABLE stock_movement IS 'Append-only signed ledger. One row per item/lot/location; transfers use two rows sharing movement_group_id. Corrections use reversal rows.';

CREATE UNIQUE INDEX stock_movement_source_event_uq ON stock_movement (tenant_id, source_event_id, location_id) WHERE source_event_id IS NOT NULL;
CREATE INDEX stock_movement_balance_idx ON stock_movement (tenant_id, item_id, stock_lot_id, location_id, occurred_at);
CREATE INDEX stock_movement_group_idx ON stock_movement (tenant_id, movement_group_id);
CREATE INDEX stock_movement_source_idx ON stock_movement (tenant_id, source_resource_type, source_resource_id);

CREATE FUNCTION aybak.validate_stock_movement()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_status text;
  v_expiry date;
BEGIN
  IF NEW.stock_lot_id IS NOT NULL AND NEW.movement_type IN ('issue','dispense','transfer_out') THEN
    SELECT quarantine_status, expiration_date INTO v_status, v_expiry
    FROM aybak.stock_lot WHERE tenant_id = NEW.tenant_id AND id = NEW.stock_lot_id;
    IF v_status <> 'available' OR (v_expiry IS NOT NULL AND v_expiry < CURRENT_DATE) THEN
      RAISE EXCEPTION 'Recalled, quarantined, or expired stock cannot be issued/dispensed/transferred';
    END IF;
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER stock_movement_validate BEFORE INSERT ON stock_movement
  FOR EACH ROW EXECUTE FUNCTION aybak.validate_stock_movement();

CREATE VIEW stock_balance WITH (security_invoker = true) AS
SELECT tenant_id, item_id, stock_lot_id, location_id, unit_ucum,
       sum(quantity_delta) AS quantity_on_hand,
       max(occurred_at) AS last_movement_at
FROM stock_movement
GROUP BY tenant_id, item_id, stock_lot_id, location_id, unit_ucum;

DO $$
DECLARE t record;
BEGIN
  FOR t IN SELECT c.oid::regclass AS table_name FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='updated_at' AND NOT a.attisdropped
    WHERE n.nspname='aybak' AND c.relkind='r' AND NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid=c.oid AND g.tgname='set_updated_at') LOOP
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
    'formulary_item','medication_request','medication_reconciliation','stock_item','stock_location',
    'stock_lot','stock_recall','dispense','medication_administration','stock_movement'
  ] LOOP
    EXECUTE format('SELECT aybak.enable_audit_trigger(%L::regclass)', 'aybak.' || t);
  END LOOP;
END
$$;

CREATE TRIGGER medication_override_immutable BEFORE UPDATE OR DELETE ON medication_override FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();
CREATE TRIGGER stock_movement_immutable BEFORE UPDATE OR DELETE ON stock_movement FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();

COMMIT;
