# AYBAK Hospital Platform — Database

Production-oriented PostgreSQL 16+/17 schema for a national hospital platform, with
executable migrations, enforced multi-tenancy, append-only audit, and an integrity
test suite that runs against a real server.

> **Status:** the schema is built and verified. The *application* is not. This
> repository remains **NO-GO for real patient data or clinical use** — see
> `docs/ENTERPRISE_AUDIT.md` and the release position in
> `docs/NATIONAL_PLATFORM_ARCHITECTURE.md`.

## Layout

```
database/
├── migrations/                     ordered, idempotent-per-version DDL
│   ├── V001__core_security_patient.sql        tenancy, staff, RBAC, patient, consent, audit
│   ├── V002__encounters_scheduling_emr.sql    encounters, scheduling, notes, medical history
│   ├── V003__pharmacy_inventory.sql           formulary, prescribing, safety, stock ledger
│   ├── V004__laboratory_radiology.sql         specimens, results, imaging, reports
│   ├── V005__billing.sql                      charges, invoices, payments, claims, ledger
│   ├── V006__integration_offline_ai.sql       outbox, sync, AI governance
│   ├── V007__roles_grants.sql                 least-privilege roles and grants
│   └── V008__national_exchange_telehealth.sql telemedicine, referrals, national exchange
├── tests/schema_integrity.sql      43 executable assertions
└── tools/
    ├── verify.cjs                  apply all migrations + run tests, CI-friendly
    └── generate_erd.py             rebuild docs/DATABASE_ERD.md from the live catalog
```

## Quick start

```bash
# 1. Disposable database (never production)
createdb aybak_dev

# 2. Apply migrations and run the integrity suite
npm install --no-save pg
DATABASE_URL=postgresql://localhost/aybak_dev node database/tools/verify.cjs

# 3. Regenerate the ERD after any schema change
pip install 'psycopg[binary]'
DATABASE_URL=postgresql://localhost/aybak_dev \
  python3 database/tools/generate_erd.py --out docs/DATABASE_ERD.md
```

Expected output of step 2 on a clean database:

```
migration OK   V001__core_security_patient.sql
...
catalog        {"tables":"103","foreign_keys":"272","indexes":"387","rls_tables":"102"}
...
43 assertions, 0 failed
```

`verify.cjs` drops the `aybak` schema first, so it must only ever run against a
disposable database.

## Design rules encoded in the schema

| Rule | How it is enforced |
|---|---|
| Tenant isolation | `tenant_id` on every owned table, composite `(tenant_id, id)` unique key, composite FKs, `FORCE ROW LEVEL SECURITY` |
| Trusted context | Backend sets `SET LOCAL app.tenant_id` / `app.staff_id`; missing context yields no rows |
| Cross-tenant linkage | Only through link tables (`patient_link_organisation`, `record_locator_entry`), never a cross-tenant FK |
| Audit | Append-only `audit_event`, field *names* not values, immutability trigger, no direct app INSERT |
| Clinical history | Document versions, result corrections, and ledger entries are append-only; corrections supersede |
| Money | `bigint` minor units + ISO-4217 `currency`; invoice totals recomputed from lines |
| Clinical quantities | `numeric` with an explicit UCUM unit; no unitless doses |
| Scheduling | GiST exclusion constraints prevent overlapping booked appointments per resource |
| Stock | Append-only `stock_movement` ledger; balances are a view; expired/recalled lots cannot be issued |
| AI | Inference blocked at the database unless the model version is approved and human-overseen |

## Roles

Created by `V007__roles_grants.sql` (NOLOGIN; attach login roles via IaC):

| Role | Purpose |
|---|---|
| `aybak_owner` / `aybak_migrator` | Schema ownership and migrations only |
| `aybak_app` | Application DML; no DDL, no audit writes, no truncate |
| `aybak_readonly` | Reporting reads |
| `aybak_analytics` | De-identified/aggregate reads |
| `aybak_integration` | Interface staging inserts and reads |
| `aybak_breakglass` | Audited emergency read access |

## Verified against

- PostgreSQL 17.11 — 8 migrations applied, 43/43 assertions passing
- PostgreSQL 16.15 — 8 migrations applied, 43/43 assertions passing

## What this schema does not do

It does not implement authorization, consent evaluation, clinical workflow, or
safety checking. Those are application responsibilities described in
`docs/NATIONAL_PLATFORM_ARCHITECTURE.md`; the database provides defense in depth,
not a substitute for them.
