-- AYBAK Hospital Platform — billing, payer, invoices, payments, and revenue ledger.
-- Requires V001–V004. All money is integer minor units; currency is ISO-4217.

BEGIN;
SET LOCAL search_path = aybak, public;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

CREATE TABLE currency (
  code char(3) PRIMARY KEY CHECK (code ~ '^[A-Z]{3}$'),
  minor_unit smallint NOT NULL CHECK (minor_unit BETWEEN 0 AND 4),
  name text NOT NULL
);

INSERT INTO currency (code, minor_unit, name) VALUES
  ('USD', 2, 'US Dollar'), ('EUR', 2, 'Euro'), ('GBP', 2, 'Pound Sterling'),
  ('AFN', 2, 'Afghan Afghani'), ('AED', 2, 'UAE Dirham'), ('SGD', 2, 'Singapore Dollar'),
  ('PKR', 2, 'Pakistan Rupee'), ('IRR', 2, 'Iranian Rial'), ('INR', 2, 'Indian Rupee'),
  ('JPY', 0, 'Japanese Yen')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE payer (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  payer_type text NOT NULL CHECK (payer_type IN ('self_pay','insurer','government','employer','charity','other')),
  code text NOT NULL,
  display_name text NOT NULL,
  currency_code char(3) NOT NULL REFERENCES currency(code),
  external_payer_id text,
  contact_details jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(contact_details) = 'object'),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, code)
);

CREATE TABLE coverage_plan (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  payer_id uuid NOT NULL,
  plan_code text NOT NULL,
  plan_name text NOT NULL,
  currency_code char(3) NOT NULL REFERENCES currency(code),
  coverage_type text NOT NULL CHECK (coverage_type IN ('medical','dental','vision','pharmacy','maternity','other')),
  effective_from date NOT NULL,
  effective_until date,
  requires_pre_authorization boolean NOT NULL DEFAULT false,
  requires_referral boolean NOT NULL DEFAULT false,
  terms_version text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, payer_id, plan_code, effective_from),
  FOREIGN KEY (tenant_id, payer_id) REFERENCES payer(tenant_id, id),
  CHECK (effective_until IS NULL OR effective_until >= effective_from)
);

CREATE TABLE patient_coverage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  coverage_plan_id uuid NOT NULL,
  member_id text NOT NULL,
  subscriber_name text,
  relationship_to_subscriber text NOT NULL CHECK (relationship_to_subscriber IN ('self','spouse','child','other')),
  priority smallint NOT NULL DEFAULT 1 CHECK (priority BETWEEN 1 AND 9),
  effective_from date NOT NULL,
  effective_until date,
  status text NOT NULL CHECK (status IN ('active','inactive','pending_verification','terminated','entered_in_error')),
  verification_reference text,
  verified_at timestamptz,
  verified_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, patient_id, priority),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, coverage_plan_id) REFERENCES coverage_plan(tenant_id, id),
  FOREIGN KEY (tenant_id, verified_by) REFERENCES practitioner(tenant_id, id),
  CHECK (effective_until IS NULL OR effective_until >= effective_from)
);

CREATE INDEX patient_coverage_lookup_idx ON patient_coverage (tenant_id, patient_id, status, priority);

CREATE TABLE payer_authorization (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  patient_coverage_id uuid NOT NULL,
  encounter_id uuid,
  service_request_id uuid,
  authorization_number text NOT NULL,
  status text NOT NULL CHECK (status IN ('draft','submitted','pending','approved','partially_approved','denied','expired','cancelled')),
  requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  decided_at timestamptz,
  valid_from date,
  valid_until date,
  approved_amount_minor bigint CHECK (approved_amount_minor >= 0),
  currency_code char(3) REFERENCES currency(code),
  denial_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, patient_coverage_id, authorization_number),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_coverage_id) REFERENCES patient_coverage(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, service_request_id) REFERENCES service_request(tenant_id, id),
  CHECK (status NOT IN ('approved','partially_approved') OR approved_amount_minor IS NOT NULL),
  CHECK (status <> 'denied' OR denial_reason IS NOT NULL),
  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from)
);

CREATE INDEX payer_authorization_worklist_idx ON payer_authorization (tenant_id, status, requested_at);

CREATE TABLE charge_master (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  facility_id uuid,
  code_system text NOT NULL,
  code_value text NOT NULL,
  display_text text NOT NULL,
  service_category text NOT NULL CHECK (service_category IN ('consultation','procedure','laboratory','radiology','pharmacy','bed','theater','other')),
  default_price_minor bigint NOT NULL CHECK (default_price_minor >= 0),
  currency_code char(3) NOT NULL REFERENCES currency(code),
  tax_code text,
  effective_from date NOT NULL,
  effective_until date,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  CHECK (effective_until IS NULL OR effective_until >= effective_from)
);

CREATE UNIQUE INDEX charge_master_price_uq ON charge_master (tenant_id, code_system, code_value, effective_from, coalesce(facility_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE TABLE charge_item (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  charge_master_id uuid,
  source_resource_type text NOT NULL,
  source_resource_id uuid,
  code_system text NOT NULL,
  code_value text NOT NULL,
  display_text text NOT NULL,
  quantity numeric(18,4) NOT NULL CHECK (quantity > 0),
  unit_price_minor bigint NOT NULL CHECK (unit_price_minor >= 0),
  gross_amount_minor bigint NOT NULL CHECK (gross_amount_minor >= 0),
  discount_amount_minor bigint NOT NULL DEFAULT 0 CHECK (discount_amount_minor >= 0),
  tax_amount_minor bigint NOT NULL DEFAULT 0 CHECK (tax_amount_minor >= 0),
  net_amount_minor bigint NOT NULL CHECK (net_amount_minor >= 0),
  currency_code char(3) NOT NULL REFERENCES currency(code),
  service_date date NOT NULL,
  posted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  posted_by uuid,
  status text NOT NULL CHECK (status IN ('draft','posted','billed','voided','entered_in_error')),
  voided_reason text,
  source_event_id uuid NOT NULL,
  idempotency_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, idempotency_key),
  UNIQUE (tenant_id, source_event_id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, charge_master_id) REFERENCES charge_master(tenant_id, id),
  CHECK (gross_amount_minor = round(quantity * unit_price_minor)),
  CHECK (net_amount_minor = gross_amount_minor - discount_amount_minor + tax_amount_minor),
  CHECK (status <> 'voided' OR voided_reason IS NOT NULL)
);

CREATE INDEX charge_item_patient_time_idx ON charge_item (tenant_id, patient_id, service_date DESC);
CREATE INDEX charge_item_unbilled_idx ON charge_item (tenant_id, status, service_date) WHERE status = 'posted';

CREATE TABLE invoice (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  encounter_id uuid,
  payer_id uuid,
  invoice_number text NOT NULL,
  invoice_type text NOT NULL CHECK (invoice_type IN ('patient','insurance','self_pay_receipt','interim')),
  status text NOT NULL CHECK (status IN ('draft','issued','partially_paid','paid','voided','written_off','entered_in_error')),
  issued_at timestamptz,
  due_date date,
  currency_code char(3) NOT NULL REFERENCES currency(code),
  subtotal_minor bigint NOT NULL DEFAULT 0 CHECK (subtotal_minor >= 0),
  discount_total_minor bigint NOT NULL DEFAULT 0 CHECK (discount_total_minor >= 0),
  tax_total_minor bigint NOT NULL DEFAULT 0 CHECK (tax_total_minor >= 0),
  total_minor bigint NOT NULL DEFAULT 0 CHECK (total_minor >= 0),
  amount_paid_minor bigint NOT NULL DEFAULT 0 CHECK (amount_paid_minor >= 0),
  balance_minor bigint NOT NULL DEFAULT 0,
  voided_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, invoice_number),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, encounter_id) REFERENCES encounter(tenant_id, id),
  FOREIGN KEY (tenant_id, payer_id) REFERENCES payer(tenant_id, id),
  CHECK (total_minor = subtotal_minor - discount_total_minor + tax_total_minor),
  CHECK (balance_minor = total_minor - amount_paid_minor),
  CHECK (amount_paid_minor <= total_minor),
  CHECK (status NOT IN ('issued','partially_paid','paid') OR issued_at IS NOT NULL),
  CHECK (status <> 'voided' OR voided_reason IS NOT NULL)
);

CREATE INDEX invoice_patient_time_idx ON invoice (tenant_id, patient_id, created_at DESC);
CREATE INDEX invoice_payer_status_idx ON invoice (tenant_id, payer_id, status, due_date);
CREATE INDEX invoice_open_balance_idx ON invoice (tenant_id, due_date) WHERE balance_minor > 0;

CREATE TABLE invoice_line (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  charge_item_id uuid,
  line_number integer NOT NULL CHECK (line_number > 0),
  description text NOT NULL CHECK (length(btrim(description)) > 0),
  code_system text,
  code_value text,
  quantity numeric(18,4) NOT NULL CHECK (quantity > 0),
  unit_price_minor bigint NOT NULL CHECK (unit_price_minor >= 0),
  gross_minor bigint NOT NULL CHECK (gross_minor >= 0),
  discount_minor bigint NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
  tax_minor bigint NOT NULL DEFAULT 0 CHECK (tax_minor >= 0),
  net_minor bigint NOT NULL CHECK (net_minor >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, invoice_id, line_number),
  FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoice(tenant_id, id),
  FOREIGN KEY (tenant_id, charge_item_id) REFERENCES charge_item(tenant_id, id),
  CHECK (gross_minor = round(quantity * unit_price_minor)),
  CHECK (net_minor = gross_minor - discount_minor + tax_minor)
);

CREATE INDEX invoice_line_charge_idx ON invoice_line (tenant_id, charge_item_id);

CREATE TABLE payment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  invoice_id uuid,
  receipt_number text NOT NULL,
  payment_method text NOT NULL CHECK (payment_method IN ('cash','card','bank_transfer','mobile_money','insurance_remittance','cheque','other')),
  status text NOT NULL CHECK (status IN ('received','allocated','partially_refunded','refunded','reversed','entered_in_error')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  currency_code char(3) NOT NULL REFERENCES currency(code),
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  received_by uuid,
  external_reference text,
  reversal_of_payment_id uuid,
  idempotency_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, receipt_number),
  UNIQUE (tenant_id, idempotency_key),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoice(tenant_id, id),
  FOREIGN KEY (tenant_id, received_by) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, reversal_of_payment_id) REFERENCES payment(tenant_id, id)
);

CREATE INDEX payment_patient_time_idx ON payment (tenant_id, patient_id, received_at DESC);
CREATE INDEX payment_invoice_idx ON payment (tenant_id, invoice_id);
CREATE INDEX payment_method_time_idx ON payment (tenant_id, payment_method, received_at);

CREATE TABLE payment_allocation (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  allocated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  allocated_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, payment_id) REFERENCES payment(tenant_id, id),
  FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoice(tenant_id, id),
  FOREIGN KEY (tenant_id, allocated_by) REFERENCES staff_principal(tenant_id, id)
);

CREATE INDEX payment_allocation_invoice_idx ON payment_allocation (tenant_id, invoice_id);
CREATE INDEX payment_allocation_payment_idx ON payment_allocation (tenant_id, payment_id);

CREATE TABLE refund (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  reason_code text NOT NULL,
  reason_text text NOT NULL CHECK (length(btrim(reason_text)) >= 5),
  status text NOT NULL CHECK (status IN ('pending_approval','approved','rejected','processed','entered_in_error')),
  requested_by uuid NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  approved_by uuid,
  approved_at timestamptz,
  processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, payment_id) REFERENCES payment(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, requested_by) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, approved_by) REFERENCES staff_principal(tenant_id, id),
  CHECK (approved_by IS NULL OR approved_by <> requested_by),
  CHECK (status NOT IN ('approved','processed') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);

CREATE INDEX refund_approval_worklist_idx ON refund (tenant_id, status, requested_at);

CREATE TABLE billing_adjustment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  invoice_id uuid,
  charge_item_id uuid,
  patient_id uuid NOT NULL,
  adjustment_type text NOT NULL CHECK (adjustment_type IN ('discount','write_off','contractual_allowance','bad_debt','correction','charity')),
  amount_minor bigint NOT NULL CHECK (amount_minor <> 0),
  currency_code char(3) NOT NULL REFERENCES currency(code),
  reason_code text NOT NULL,
  reason_text text NOT NULL CHECK (length(btrim(reason_text)) >= 5),
  status text NOT NULL CHECK (status IN ('requested','approved','rejected','posted','reversed')),
  requested_by uuid NOT NULL,
  approved_by uuid,
  approved_at timestamptz,
  posted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, invoice_id) REFERENCES invoice(tenant_id, id),
  FOREIGN KEY (tenant_id, charge_item_id) REFERENCES charge_item(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, requested_by) REFERENCES staff_principal(tenant_id, id),
  FOREIGN KEY (tenant_id, approved_by) REFERENCES staff_principal(tenant_id, id),
  CHECK (num_nonnulls(invoice_id, charge_item_id) >= 1),
  CHECK (approved_by IS NULL OR approved_by <> requested_by),
  CHECK (status NOT IN ('approved','posted') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);

CREATE TABLE claim (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  payer_id uuid NOT NULL,
  patient_coverage_id uuid NOT NULL,
  claim_number text NOT NULL,
  claim_type text NOT NULL CHECK (claim_type IN ('institutional','professional','pharmacy','dental')),
  status text NOT NULL CHECK (status IN ('draft','scrubbed','submitted','accepted','rejected','in_review','adjudicated','appealed','paid','closed','entered_in_error')),
  total_claimed_minor bigint NOT NULL CHECK (total_claimed_minor >= 0),
  total_approved_minor bigint CHECK (total_approved_minor >= 0),
  currency_code char(3) NOT NULL REFERENCES currency(code),
  submitted_at timestamptz,
  adjudicated_at timestamptz,
  remittance_reference text,
  denial_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, claim_number),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, payer_id) REFERENCES payer(tenant_id, id),
  FOREIGN KEY (tenant_id, patient_coverage_id) REFERENCES patient_coverage(tenant_id, id),
  CHECK (status NOT IN ('submitted','accepted') OR submitted_at IS NOT NULL),
  CHECK (status <> 'rejected' OR denial_reason IS NOT NULL)
);

CREATE INDEX claim_status_idx ON claim (tenant_id, payer_id, status, submitted_at);
CREATE INDEX claim_patient_idx ON claim (tenant_id, patient_id, created_at DESC);

CREATE TABLE claim_line (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  claim_id uuid NOT NULL,
  invoice_line_id uuid,
  line_number integer NOT NULL CHECK (line_number > 0),
  code_system text NOT NULL,
  code_value text NOT NULL,
  quantity numeric(18,4) NOT NULL CHECK (quantity > 0),
  claimed_minor bigint NOT NULL CHECK (claimed_minor >= 0),
  approved_minor bigint CHECK (approved_minor >= 0),
  adjustment_reason_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, claim_id, line_number),
  FOREIGN KEY (tenant_id, claim_id) REFERENCES claim(tenant_id, id),
  FOREIGN KEY (tenant_id, invoice_line_id) REFERENCES invoice_line(tenant_id, id)
);

CREATE INDEX claim_line_invoice_idx ON claim_line (tenant_id, invoice_line_id);

CREATE TABLE financial_ledger_entry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL,
  entry_group_id uuid NOT NULL,
  patient_id uuid,
  facility_id uuid,
  entry_type text NOT NULL CHECK (entry_type IN ('charge','invoice','payment','refund','adjustment','write_off','claim_remittance','reversal')),
  debit_account text NOT NULL,
  credit_account text NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  currency_code char(3) NOT NULL REFERENCES currency(code),
  source_resource_type text NOT NULL,
  source_resource_id uuid NOT NULL,
  source_event_id uuid NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  description text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid,
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, entry_group_id, debit_account, credit_account, amount_minor),
  FOREIGN KEY (tenant_id, patient_id) REFERENCES patient(tenant_id, id),
  FOREIGN KEY (tenant_id, facility_id) REFERENCES facility(tenant_id, id),
  CHECK (debit_account <> credit_account)
);

COMMENT ON TABLE financial_ledger_entry IS 'Append-only double-entry postings. Never edit or delete; reverse with an opposite entry_group.';

CREATE INDEX financial_ledger_source_idx ON financial_ledger_entry (tenant_id, source_resource_type, source_resource_id);
CREATE INDEX financial_ledger_patient_time_idx ON financial_ledger_entry (tenant_id, patient_id, occurred_at DESC);
CREATE INDEX financial_ledger_account_idx ON financial_ledger_entry (tenant_id, debit_account, occurred_at);

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
    'payer','coverage_plan','patient_coverage','payer_authorization','charge_master','charge_item',
    'invoice','invoice_line','payment','payment_allocation','refund','billing_adjustment','claim','claim_line'
  ] LOOP
    EXECUTE format('SELECT aybak.enable_audit_trigger(%L::regclass)', 'aybak.' || t);
  END LOOP;
END
$$;

CREATE TRIGGER financial_ledger_entry_immutable BEFORE UPDATE OR DELETE ON financial_ledger_entry FOR EACH ROW EXECUTE FUNCTION aybak.prevent_mutation();

-- Invoice totals must equal the sum of their lines; enforced on line insert/update/delete.
CREATE FUNCTION aybak.validate_invoice_totals()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_invoice uuid := COALESCE(NEW.invoice_id, OLD.invoice_id);
  v_subtotal bigint; v_discount bigint; v_tax bigint; v_net bigint;
BEGIN
  SELECT coalesce(sum(gross_minor),0), coalesce(sum(discount_minor),0), coalesce(sum(tax_minor),0), coalesce(sum(net_minor),0)
    INTO v_subtotal, v_discount, v_tax, v_net
  FROM aybak.invoice_line WHERE tenant_id = COALESCE(NEW.tenant_id, OLD.tenant_id) AND invoice_id = v_invoice;
  UPDATE aybak.invoice
     SET subtotal_minor = v_subtotal, discount_total_minor = v_discount, tax_total_minor = v_tax,
         total_minor = v_net, balance_minor = v_net - amount_paid_minor
   WHERE tenant_id = COALESCE(NEW.tenant_id, OLD.tenant_id) AND id = v_invoice;
  RETURN NULL;
END
$$;

CREATE TRIGGER invoice_line_totals_ai AFTER INSERT ON invoice_line FOR EACH ROW EXECUTE FUNCTION aybak.validate_invoice_totals();
CREATE TRIGGER invoice_line_totals_au AFTER UPDATE ON invoice_line FOR EACH ROW EXECUTE FUNCTION aybak.validate_invoice_totals();
CREATE TRIGGER invoice_line_totals_ad AFTER DELETE ON invoice_line FOR EACH ROW EXECUTE FUNCTION aybak.validate_invoice_totals();

CREATE FUNCTION aybak.validate_payment_allocation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_payment_total bigint; v_allocated bigint; v_status text; v_patient uuid; v_invoice_patient uuid;
BEGIN
  SELECT amount_minor, status, patient_id INTO v_payment_total, v_status, v_patient
    FROM aybak.payment WHERE tenant_id = NEW.tenant_id AND id = NEW.payment_id;
  IF v_status IN ('reversed','refunded','entered_in_error') THEN
    RAISE EXCEPTION 'Cannot allocate a % payment', v_status USING ERRCODE = '23514';
  END IF;
  SELECT patient_id INTO v_invoice_patient FROM aybak.invoice WHERE tenant_id = NEW.tenant_id AND id = NEW.invoice_id;
  IF v_invoice_patient <> v_patient THEN
    RAISE EXCEPTION 'Payment and invoice belong to different patients' USING ERRCODE = '23514';
  END IF;
  SELECT coalesce(sum(amount_minor),0) INTO v_allocated FROM aybak.payment_allocation
   WHERE tenant_id = NEW.tenant_id AND payment_id = NEW.payment_id
     AND (TG_OP = 'INSERT' OR id <> NEW.id);
  IF v_allocated + NEW.amount_minor > v_payment_total THEN
    RAISE EXCEPTION 'Allocation exceeds payment amount' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER payment_allocation_validate BEFORE INSERT OR UPDATE ON payment_allocation
  FOR EACH ROW EXECUTE FUNCTION aybak.validate_payment_allocation();

CREATE FUNCTION aybak.refresh_invoice_paid()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_invoice uuid; v_paid bigint; v_total bigint; v_status text;
BEGIN
  v_invoice := COALESCE(NEW.invoice_id, OLD.invoice_id);
  SELECT coalesce(sum(amount_minor),0) INTO v_paid FROM aybak.payment_allocation
   WHERE tenant_id = COALESCE(NEW.tenant_id, OLD.tenant_id) AND invoice_id = v_invoice;
  SELECT total_minor, status INTO v_total, v_status FROM aybak.invoice
   WHERE tenant_id = COALESCE(NEW.tenant_id, OLD.tenant_id) AND id = v_invoice;
  UPDATE aybak.invoice
     SET amount_paid_minor = v_paid,
         balance_minor = v_total - v_paid,
         status = CASE
           WHEN v_status IN ('voided','written_off','entered_in_error','draft') THEN v_status
           WHEN v_paid = 0 THEN 'issued'
           WHEN v_paid < v_total THEN 'partially_paid'
           ELSE 'paid' END
   WHERE tenant_id = COALESCE(NEW.tenant_id, OLD.tenant_id) AND id = v_invoice;
  RETURN NULL;
END
$$;

CREATE TRIGGER payment_allocation_paid_ai AFTER INSERT ON payment_allocation FOR EACH ROW EXECUTE FUNCTION aybak.refresh_invoice_paid();
CREATE TRIGGER payment_allocation_paid_au AFTER UPDATE ON payment_allocation FOR EACH ROW EXECUTE FUNCTION aybak.refresh_invoice_paid();
CREATE TRIGGER payment_allocation_paid_ad AFTER DELETE ON payment_allocation FOR EACH ROW EXECUTE FUNCTION aybak.refresh_invoice_paid();

CREATE FUNCTION aybak.prevent_posted_charge_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status IN ('billed','voided') AND NEW.status = OLD.status AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'Billed or voided charges are immutable; post a correction instead' USING ERRCODE = '55000';
  END IF;
  IF OLD.status IN ('voided','entered_in_error') THEN
    RAISE EXCEPTION 'Terminal charge state cannot change' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER charge_item_posted_guard BEFORE UPDATE ON charge_item
  FOR EACH ROW EXECUTE FUNCTION aybak.prevent_posted_charge_mutation();

COMMIT;
