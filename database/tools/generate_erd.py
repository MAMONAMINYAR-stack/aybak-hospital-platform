#!/usr/bin/env python3
"""Generate a Mermaid ERD and table inventory from a live AYBAK schema.

Unlike a hand-drawn diagram, this reads pg_catalog so the document cannot drift
from the migrations. Requires a PostgreSQL connection string in DATABASE_URL
(or --dsn) and the `psycopg` 3 driver.

Usage:
    python3 database/tools/generate_erd.py --dsn postgresql://user@host/db \
        --out docs/DATABASE_ERD.md
"""

from __future__ import annotations

import argparse
import os
import sys

MODULES: list[tuple[str, str]] = [
    ("Tenancy, identity, and security", "organization facility department staff_principal practitioner role_template user_role_assignment worker_assignment professional_credential training_privilege"),
    ("Patient record and identity resolution", "patient patient_identifier person_name patient_contact_point patient_address patient_link identity_match_review consent_directive care_relationship break_glass_session access_export"),
    ("Audit", "audit_event"),
    ("Encounters, scheduling, and clinical documents", "encounter care_team_member location_assignment schedule_resource resource_unavailability appointment appointment_transition clinical_document document_version signature"),
    ("Medical history and clinical findings", "problem allergy_intolerance observation immunization procedure_record family_history social_history service_request diagnostic_result result_value clinical_provenance"),
    ("Pharmacy, medication safety, and inventory", "formulary_item medication_request medication_safety_review medication_override stock_item stock_location stock_lot stock_recall dispense medication_administration medication_reconciliation stock_movement"),
    ("Laboratory", "lab_test_definition lab_order specimen specimen_event reference_range lab_result delta_check"),
    ("Radiology", "imaging_order imaging_protocol imaging_study_ref radiology_report radiology_report_version critical_result_notification external_result_import"),
    ("Billing, payer, and revenue", "currency payer coverage_plan patient_coverage payer_authorization charge_master charge_item invoice invoice_line payment payment_allocation refund billing_adjustment claim claim_line financial_ledger_entry"),
    ("Integration, offline sync, and AI", "integration_endpoint inbound_message outbox_event delivery_attempt sync_device sync_change_log ai_model_registration ai_inference_record ai_output_review ai_model_feedback"),
    ("Telemedicine and referrals", "telehealth_session referral consent_directive encounter patient practitioner facility organization"),
    ("National exchange and Health ID", "national_health_id patient_link_organisation record_locator_entry sharing_agreement record_share_request record_share_result organization patient"),
]

# Tables included in each per-module ERD diagram (kept readable on purpose).
ERD_GROUPS: list[tuple[str, list[str]]] = [
    ("1. Tenancy, security, and audit", ["organization", "facility", "department", "staff_principal", "practitioner", "role_template", "user_role_assignment", "professional_credential", "audit_event", "break_glass_session"]),
    ("2. Patient record", ["organization", "patient", "patient_identifier", "person_name", "patient_contact_point", "patient_address", "patient_link", "identity_match_review", "consent_directive", "care_relationship"]),
    ("3. Encounters and scheduling", ["patient", "facility", "encounter", "care_team_member", "location_assignment", "schedule_resource", "resource_unavailability", "appointment", "appointment_transition", "clinical_document", "document_version", "signature"]),
    ("4. Medical history", ["patient", "encounter", "problem", "allergy_intolerance", "observation", "immunization", "procedure_record", "family_history", "social_history"]),
    ("5. Orders and results", ["patient", "encounter", "service_request", "diagnostic_result", "result_value", "lab_order", "specimen", "specimen_event", "lab_result", "imaging_order", "imaging_study_ref", "radiology_report", "radiology_report_version", "critical_result_notification"]),
    ("6. Pharmacy and inventory", ["medication_request", "formulary_item", "medication_safety_review", "medication_override", "dispense", "medication_administration", "medication_reconciliation", "stock_item", "stock_location", "stock_lot", "stock_movement", "stock_recall"]),
    ("7. Billing and revenue", ["patient", "encounter", "payer", "coverage_plan", "patient_coverage", "payer_authorization", "charge_master", "charge_item", "invoice", "invoice_line", "payment", "payment_allocation", "refund", "billing_adjustment", "claim", "claim_line", "financial_ledger_entry"]),
    ("8. Integration, sync, and AI", ["outbox_event", "delivery_attempt", "integration_endpoint", "inbound_message", "sync_device", "sync_change_log", "ai_model_registration", "ai_inference_record", "ai_output_review", "ai_model_feedback"]),
    ("9. Telemedicine and referrals", ["patient", "encounter", "practitioner", "facility", "consent_directive", "telehealth_session", "referral", "service_request"]),
    ("10. National exchange and Health ID", ["organization", "patient", "national_health_id", "patient_link_organisation", "record_locator_entry", "sharing_agreement", "record_share_request", "record_share_result"]),
]

QUERY_TABLES = """
SELECT c.relname AS table_name,
       obj_description(c.oid, 'pg_class') AS comment,
       (SELECT count(*) FROM pg_attribute a
         WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS column_count,
       (SELECT count(*) FROM pg_index i WHERE i.indrelid = c.oid) AS index_count,
       c.relrowsecurity AS rls
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'aybak' AND c.relkind = 'r'
ORDER BY c.relname
"""

QUERY_COLUMNS = """
SELECT c.relname AS table_name, a.attname AS column_name,
       format_type(a.atttypid, a.atttypmod) AS data_type,
       a.attnotnull AS not_null,
       col_description(c.oid, a.attnum) AS comment
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'aybak' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY c.relname, a.attnum
"""

QUERY_FKS = """
SELECT con.conname,
       src.relname AS source_table,
       tgt.relname AS target_table,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
JOIN pg_class src ON src.oid = con.conrelid
JOIN pg_class tgt ON tgt.oid = con.confrelid
JOIN pg_namespace n ON n.oid = con.connamespace
WHERE n.nspname = 'aybak' AND con.contype = 'f'
ORDER BY src.relname, con.conname
"""

QUERY_INDEXES = """
SELECT tablename, indexname, indexdef
FROM pg_indexes WHERE schemaname = 'aybak'
ORDER BY tablename, indexname
"""


def run_sql(conn, sql: str) -> list[list[str]]:
    with conn.cursor() as cur:
        cur.execute(sql)
        return [["" if v is None else str(v) for v in row] for row in cur.fetchall()]


def load_catalog(dsn: str):
    try:
        import psycopg
    except ImportError:
        sys.exit("pip install 'psycopg[binary]' to run this generator")
    with psycopg.connect(dsn) as conn:
        tables = run_sql(conn, QUERY_TABLES)
        columns = run_sql(conn, QUERY_COLUMNS)
        fks = run_sql(conn, QUERY_FKS)
        indexes = run_sql(conn, QUERY_INDEXES)
    return tables, columns, fks, indexes


def key_columns(columns: list[list[str]], table: str) -> list[tuple[str, str]]:
    """Key highlighting: the uuid primary key plus columns that look like FKs."""
    out: list[tuple[str, str]] = []
    for table_name, column, data_type, *_ in columns:
        if table_name != table:
            continue
        if column == "id" or (column.endswith("_id") and data_type == "uuid"):
            out.append((data_type, column))
    return out


def render_erd(fks: list[list[str]], columns: list[list[str]]) -> str:
    """Emit one Mermaid erDiagram per module.

    Relationship direction follows Mermaid's ``LEFT ||--o{ RIGHT`` form, where
    LEFT is the referenced parent and RIGHT the referencing child.
    """
    out: list[str] = []
    for title, wanted in ERD_GROUPS:
        present = [t for t in wanted if any(c[0] == t for c in columns)]
        group_fks = [f for f in fks if f[1] in present and f[2] in present]
        out.append(f"### {title}\n")
        out.append("```mermaid")
        out.append("erDiagram")
        for table in present:
            keys = sorted(key_columns(columns, table), key=lambda k: (k[1] != "id", k[1]))[:8]
            out.append(f"  {table} {{")
            for data_type, col in keys:
                out.append(f"    {data_type} {col}")
            out.append("  }")
        for source, target, definition in ((f[1], f[2], f[3]) for f in group_fks):
            cols = definition.split("(")[1].split(")")[0]
            if "NOT NULL" in definition:
                cardinality = "||--o{"
            else:
                cardinality = "|o--o{"
            out.append(f'  {target} {cardinality} {source} : "{cols}"')
        out.append("```\n")
    return "\n".join(out)


def render_module_table(columns: list[list[str]], tables: list[list[str]], fks: list[list[str]]) -> str:
    by_table: dict[str, list[str]] = {}
    for row in tables:
        by_table[row[0]] = row
    fk_by_source: dict[str, list[str]] = {}
    for f in fks:
        fk_by_source.setdefault(f[1], []).append(f"{f[2]} ({f[3].split('(')[1].split(')')[0]})")

    lines = [
        "| Module | Table | Columns | FKs out | Indexes | RLS | Purpose |",
        "|---|---|---|---|---|---|---|",
    ]
    seen: set[str] = set()
    for module, table_names in MODULES:
        for name in table_names.split():
            if name not in by_table:
                continue
            seen.add(name)
            row = by_table[name]
            targets = fk_by_source.get(name, [])
            purpose = (row[1] or "").split(".")[0] or "—"
            lines.append(
                f"| {module} | `{name}` | {row[2]} | {len(targets)} | {row[3]} | "
                f"{'yes' if row[4] == 't' else 'no'} | {purpose} |"
            )
    missing = sorted(set(by_table) - seen)
    for name in missing:
        row = by_table[name]
        lines.append(f"| Uncategorised | `{name}` | {row[2]} | {len(fk_by_source.get(name, []))} | {row[3]} | "
                     f"{'yes' if row[4] == 't' else 'no'} | {row[1] or '—'} |")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dsn", default=os.environ.get("DATABASE_URL"), required=False)
    parser.add_argument("--out", default="docs/DATABASE_ERD.md")
    args = parser.parse_args()
    if not args.dsn:
        sys.exit("Provide --dsn or set DATABASE_URL")

    tables, columns, fks, indexes = load_catalog(args.dsn)

    doc = [
        "# AYBAK Hospital Platform — Entity Relationship Diagram",
        "",
        "> Generated from the live PostgreSQL catalog by `database/tools/generate_erd.py`.",
        "> Do not edit by hand; regenerate after every migration.",
        "",
        f"**{len(tables)} tables, {len(fks)} foreign keys, {len(indexes)} indexes.**",
        "",
        "Every tenant-owned table carries `tenant_id` and a composite "
        "`(tenant_id, id)` unique key so that every relationship is tenant-safe "
        "by construction rather than by convention.",
        "",
        "## Relationship map",
        "",
        "```mermaid",
        "flowchart LR",
        "  org[organization] --> fac[facility]",
        "  fac --> dept[department]",
        "  org --> staff[staff_principal]",
        "  staff --> pract[practitioner]",
        "  org --> pat[patient]",
        "  pat --> enc[encounter]",
        "  enc --> appt[appointment]",
        "  enc --> doc[clinical_document]",
        "  enc --> sr[service_request]",
        "  sr --> lab[lab_order]",
        "  sr --> img[imaging_order]",
        "  sr --> med[medication_request]",
        "  enc --> chg[charge_item]",
        "  chg --> inv[invoice]",
        "  inv --> pay[payment]",
        "  pay --> led[financial_ledger_entry]",
        "  lab --> res[diagnostic_result]",
        "  img --> res",
        "  med --> disp[dispense]",
        "  disp --> inv",
        "  pat --> aud[audit_event]",
        "  enc --> out[outbox_event]",
        "```",
        "",
        "## Module diagrams",
        "",
        render_erd(fks, columns),
        "## Table inventory",
        "",
        render_module_table(columns, tables, fks),
        "",
        "## Index inventory",
        "",
        "Indexes are listed per table and include both plain B-tree access paths and "
        "the specialised structures that carry correctness guarantees "
        "(GiST exclusion constraints for scheduling, BRIN for the audit time axis, "
        "partial indexes for worklists and open balances).",
        "",
        "| Table | Index | Definition |",
        "|---|---|---|",
    ]
    for table, index, definition in indexes:
        safe_definition = definition.replace("|", "\\|")
        doc.append(f"| `{table}` | `{index}` | `{safe_definition}` |")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write("\n".join(doc) + "\n")
    print(f"wrote {args.out}: {len(tables)} tables, {len(fks)} FKs, {len(indexes)} indexes")


if __name__ == "__main__":
    main()
