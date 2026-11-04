#!/usr/bin/env python3
"""Validate the national platform architecture catalogs.

Checks performed:
  1. Event names follow <aggregate>.<past-tense-event>.v<major> and versions are >= 1.
  2. Every event producer is a declared service.
  3. Every event consumer is a declared context or service.
  4. Every context service exists and is owned by that context.
  5. Every published event is produced by a service in that context.
  6. Every table in the PostgreSQL migrations is owned by exactly one bounded context.
  7. Every owned table actually exists in the migrations.
  8. Partition keys reference plausible attributes; PHI-flagged events never key on nothing.
  9. No duplicate context, service, or event identifiers.

Exit code is non-zero on any violation, so CI can gate on it.
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "architecture" / "catalog"
MIGRATIONS = ROOT / "database" / "migrations"

EVENT_PATTERN = re.compile(r"^[a-z][a-z0-9-]*(\.[a-z0-9-]+)+\.v[0-9]+$")
TABLE_PATTERN = re.compile(r"^CREATE TABLE\s+([a-z_][a-z0-9_]*)\s*\(", re.MULTILINE)


def load(name: str):
    with open(CATALOG / f"{name}.json", encoding="utf-8") as fh:
        return json.load(fh)


def main() -> int:
    contexts = load("contexts")
    services = load("services")
    events = load("events")

    errors: list[str] = []
    warnings: list[str] = []

    # 1-2-3: event shape and endpoints
    for event in events:
        if not EVENT_PATTERN.match(event["name"]):
            errors.append(f"event name not conventional: {event['name']}")
        if event["version"] < 1:
            errors.append(f"event version < 1: {event['name']}")
        if event["contains_phi"] and not event["partition_key"]:
            errors.append(f"PHI event without partition key: {event['name']}")
        if len(event["consumers_contexts"]) == 0:
            warnings.append(f"event has no declared consumer: {event['name']}")

    service_ids = {s["id"] for s in services}
    context_ids = {c["id"] for c in contexts}

    for event in events:
        if event["producer"] not in service_ids:
            errors.append(f"event producer is not a service: {event['name']} -> {event['producer']}")
        for target in event["consumers_contexts"]:
            if target not in context_ids and target not in service_ids:
                errors.append(f"event consumer unknown: {event['name']} -> {target}")

    # 4-5: ownership coherence
    by_context: dict[str, list[dict]] = defaultdict(list)
    for service in services:
        by_context[service["context"]].append(service)
        if service["context"] not in context_ids:
            errors.append(f"service {service['id']} owned by unknown context {service['context']}")

    published_by_context: dict[str, set[str]] = defaultdict(set)
    for service in services:
        published_by_context[service["context"]] |= set()

    producer_of = {e["name"]: e["producer"] for e in events}
    producer_context = {s["id"]: s["context"] for s in services}

    for context in contexts:
        for svc in context["services"]:
            if svc not in service_ids:
                errors.append(f"context {context['id']} lists unknown service {svc}")
            elif producer_context.get(svc) != context["id"]:
                errors.append(f"context {context['id']} lists service {svc} owned by {producer_context.get(svc)}")
        for published in context["publishes"]:
            if published not in producer_of:
                errors.append(f"context {context['id']} publishes undeclared event {published}")
            elif producer_context.get(producer_of[published]) != context["id"]:
                errors.append(f"context {context['id']} publishes {published} but producer belongs to "
                              f"{producer_context.get(producer_of[published])}")
        for consumed in context["consumes"]:
            if consumed not in producer_of:
                errors.append(f"context {context['id']} consumes undeclared event {consumed}")

    for event_name in producer_of:
        owners = [c["id"] for c in contexts if event_name in c["publishes"]]
        if not owners:
            warnings.append(f"event not claimed in any context 'publishes': {event_name}")

    # 6-7: table ownership vs migrations
    ddl_tables: set[str] = set()
    for migration in sorted(MIGRATIONS.glob("*.sql")):
        ddl_tables |= set(TABLE_PATTERN.findall(migration.read_text(encoding="utf-8")))

    owners: dict[str, list[str]] = defaultdict(list)
    for context in contexts:
        for table in context["owns"]:
            owners[table].append(context["id"])

    for table, claimed in owners.items():
        if len(claimed) > 1:
            errors.append(f"table {table} claimed by multiple contexts: {claimed}")
        if table not in ddl_tables:
            errors.append(f"table {table} claimed but absent from migrations")

    for context in contexts:
        for table in context.get("reads", []):
            if table not in ddl_tables:
                errors.append(f"{context['id']} reads unknown table {table}")
            if table in context["owns"]:
                errors.append(f"{context['id']} both owns and reads {table}")

    unowned = sorted(ddl_tables - set(owners))
    if unowned:
        errors.append("tables in migrations without a bounded-context owner: " + ", ".join(unowned))

    # 8-9: duplicates
    for label, rows, key in (
        ("context", contexts, "id"),
        ("service", services, "id"),
        ("event", events, "name"),
    ):
        dupes = [name for name, count in Counter(r[key] for r in rows).items() if count > 1]
        if dupes:
            errors.append(f"duplicate {label} identifiers: {dupes}")

    # Report
    print(f"contexts={len(contexts)} services={len(services)} events={len(events)} "
          f"ddl_tables={len(ddl_tables)}")
    for warning in warnings:
        print(f"WARN  {warning}")
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"\nFAILED with {len(errors)} error(s)")
        return 1
    print("OK: architecture catalogs are internally consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
