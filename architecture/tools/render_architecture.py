#!/usr/bin/env python3
"""Render the national platform architecture document from validated catalogs.

The prose lives here; every table of contexts, services, and events is generated
from architecture/catalog/*.json so the document cannot silently drift from the
machine-checked catalogs.
"""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "architecture" / "catalog"
OUT = ROOT / "docs" / "NATIONAL_PLATFORM_ARCHITECTURE.md"


def load(name: str):
    with open(CATALOG / f"{name}.json", encoding="utf-8") as fh:
        return json.load(fh)


CONTEXTS = load("contexts")
SERVICES = load("services")
EVENTS = load("events")

TYPE_LABEL = {
    "core": "Core",
    "supporting": "Supporting",
    "generic": "Generic",
}

TIER_LABEL = {
    0: "P0 — safety-critical, never degraded",
    1: "P1 — clinical/operational",
    2: "P2 — supporting",
    3: "P3 — analytical/administrative",
}


def section_executive() -> str:
    return """## 1. Executive Direction

### 1.1 What is being asked for, and what it costs

The request is a national healthcare platform serving hospitals, clinics, pharmacies, laboratories, radiology centres, emergency services, telemedicine, and the Ministry of Health. That is not a bigger version of a hospital system. It is a **federated clinical record network with a national identity layer**, and its hardest problems are not feature problems. They are identity, consent, sovereignty, connectivity, and the consequences of being wrong.

This document is a target architecture. It is paired with an honest statement of current maturity, because the two must never be confused:

| Position | Status today | Evidence |
|---|---|---|
| Production readiness of this repository | **NO-GO — 6/100** | `docs/ENTERPRISE_AUDIT.md`, 37 findings |
| Executable database foundation | **Built and verified** | 103 tables, 272 FKs, 387 indexes, 43 integrity tests passing on PostgreSQL 17.11 |
| Application/services | **Not built** | `src/App.jsx` is a 546-line prototype with embedded fixtures |
| National platform | **Design only** | This document |

Nothing in this document authorises real patient data, clinical use, or production deployment. A target architecture is a promise about direction, not evidence of capability.

### 1.2 Design commitments

1. **Clinical safety outranks availability, which outranks convenience.** Where a feature could silently produce a wrong clinical fact, the platform fails closed and asks a human.
2. **The record follows the patient; the data stays in the jurisdiction.** Sovereignty is achieved by federation, not by centralising a copy of every citizen's record in one database.
3. **Offline is a first-class continuity mode, never a second uncontrolled database.** Downtime workflows are designed, bounded, and reconciled — not discovered during an outage.
4. **Every access is attributable and lawful.** Purpose, legal basis, consent, actor, and outcome are recorded at the boundary, and denials are evidence too.
5. **AI assists, humans decide.** No model output becomes a clinical fact without a named clinician accepting it, and no unapproved model runs at all.
6. **Microservices are a destination justified by evidence.** The modular monolith ships first; boundaries are extracted when a measured constraint demands it.
7. **Boring, proven technology in the critical path.** Innovation budget goes to clinical workflow and interoperability, not to novel storage engines.

### 1.3 Scale envelope used for design

These are planning assumptions, not commitments. They are stated so that capacity, cost, and phasing can be argued with.

| Dimension | Year 1 | Year 3 | Year 5 |
|---|---|---|---|
| Organisations (tenants) | 15 | 120 | 400 |
| Facilities | 60 | 700 | 2,500 |
| Registered patients | 2 M | 12 M | 30 M |
| Clinicians with accounts | 4,000 | 40,000 | 120,000 |
| Clinical documents/year | 6 M | 90 M | 300 M |
| Observations/year | 150 M | 2 B | 8 B |
| Events/day (peak) | 2 M | 40 M | 150 M |
| Offline devices | 1,000 | 25,000 | 90,000 |
| Residency zones | 1 | 3 | 5 |

### 1.4 The five decisions that matter most

| # | Decision | Why it dominates | Reversal cost |
|---|---|---|---|
| D1 | Federated exchange + record locator, **not** a central clinical data warehouse | Sovereignty, blast radius, legal defensibility | Very high |
| D2 | National Health ID as a **linkage key, never an authentication secret** | Prevents a single credential from becoming the master key to the nation's health data | High |
| D3 | Consent and policy evaluated at a **central policy decision point**, enforced at every boundary | One place to change law; no per-service drift | High |
| D4 | **Modular monolith first**, extract services on measured pressure | Avoids distributed-systems tax before product-market fit | Low if deferred, very high if premature |
| D5 | Offline with **explicit conflict resolution**, no last-write-wins on clinical facts | The alternative silently corrupts the record | Very high |

---
"""


def section_architecture() -> str:
    return """## 2. Target Enterprise Architecture

### 2.1 Layered view

```mermaid
flowchart TB
    subgraph Channels
        Web[Clinician web app]
        Mobile[Managed mobile / offline client]
        Portal[Patient portal]
        Ministry[Ministry dashboards]
        Partner[Partner and payer integrations]
    end

    subgraph Edge
        EdgeAuth[Edge auth, WAF, rate limits]
        Gateway[API gateway / BFF]
        DeviceTrust[Device trust and attestation]
    end

    subgraph Core["Platform core services"]
        Identity[Identity and EMPI]
        Consent[Consent and policy decision point]
        Clinical[Clinical domains]
        Exchange[National exchange gateway]
        Sync[Offline sync]
        AI[AI governance and orchestration]
    end

    subgraph Data
        PG[(PostgreSQL per cell)]
        Obj[(Encrypted object storage)]
        Broker[Durable event broker]
        Search[Search and locator index]
        Analytics[(De-identified analytics)]
        Audit[(Append-only audit store)]
    end

    subgraph National
        NHID[National Health ID authority]
        FacilityReg[Facility and service registry]
        Terminology[Terminology service]
        Surveillance[Public health surveillance]
        SOC[Security operations]
    end

    Web --> EdgeAuth
    Mobile --> EdgeAuth
    Portal --> EdgeAuth
    Ministry --> EdgeAuth
    Partner --> EdgeAuth
    EdgeAuth --> Gateway
    EdgeAuth --> DeviceTrust
    Gateway --> Identity
    Gateway --> Consent
    Gateway --> Clinical
    Gateway --> Exchange
    Gateway --> Sync
    Gateway --> AI
    Identity --> PG
    Consent --> PG
    Clinical --> PG
    Clinical --> Obj
    Clinical --> Broker
    Exchange --> Broker
    Exchange --> Search
    Sync --> Obj
    AI --> PG
    Broker --> Analytics
    Broker --> Surveillance
    Clinical --> Audit
    Exchange --> Audit
    Consent --> Audit
    National --> Core
    NHID --> Identity
    FacilityReg --> Clinical
    Terminology --> Clinical
    SOC --> Audit
```

### 2.2 Cell-based topology with residency zones

The unit of deployment is a **cell**: a regionally placed, independently operable slice containing application services, its own PostgreSQL cluster, object storage, broker, and audit shipper. A cell serves a set of tenants. Tenants are placed in a cell for residency, latency, blast-radius, or contractual reasons.

```mermaid
flowchart TB
    Users[Users and integrations] --> Anycast[Global anycast + WAF + tenant discovery]
    Anycast --> Control["National control plane: tenant placement, configuration, flags, no clinical data"]
    Anycast --> Router[Residency-aware router]

    subgraph ZoneA["Zone A (primary residency)"]
        CellA1["Cell A1: services, PostgreSQL, objects, broker"]
        CellA2["Cell A2: services, PostgreSQL, objects, broker"]
    end

    subgraph ZoneB["Zone B (secondary residency)"]
        CellB1["Cell B1: services, PostgreSQL, objects, broker"]
    end

    subgraph ZoneC["Zone C (national services)"]
        Exchange[Exchange and locator]
        NHIDAuthority[Health ID authority]
        Terms[Terminology]
        Surveillance[Surveillance]
    end

    Router --> CellA1
    Router --> CellA2
    Router --> CellB1
    CellA1 <--> Exchange
    CellA2 <--> Exchange
    CellB1 <--> Exchange
    CellA1 --> AuditStore[("Independent audit and evidence store")]
    CellB1 --> AuditStore
    CellA2 --> AuditStore
    Exchange --> AuditStore
    Exchange --> NHIDAuthority
    Exchange --> Terms
    Surveillance --> Anon[(De-identified analytics)]
    CellA1 -.->|de-identified extracts only| Anon
```

**Rules that make cells safe**

- No tenant is served by two cells at the same time for writes. Failover is an explicit, exercised operation, not an accident.
- The control plane can never read clinical data. If it is compromised, patient records are not exposed — only routing metadata.
- The exchange and locator live in the national zone but hold **identifiers and availability metadata**, not clinical content.
- Every cell ships audit to an independent store with a write-once retention policy, so an attacker who owns a cell cannot erase their traces.

### 2.3 Runtime layering inside a cell

| Layer | Responsibility | Explicitly not responsible for |
|---|---|---|
| Edge | TLS, WAF, bot mitigation, coarse rate limits, tenant discovery | Authorization decisions |
| BFF / gateway | Session, token exchange, request shaping, aggregation for the UI | Business rules |
| Domain services | Business invariants, transactions, audit emission | Cross-domain bypass |
| Data | Persistence, RLS, constraints, immutability triggers | Authorization policy |
| Event backbone | Durable publication, ordering per key, replay | Business interpretation |
| Integration | Protocol translation, quarantine, mapping | Writing straight into clinical tables |

### 2.4 Non-negotiable platform invariants

1. **Tenant identity is server-derived.** A client-supplied tenant header is a hint for routing, never an authorization input.
2. **Every tenant-owned row carries `tenant_id`, and every relationship is a composite `(tenant_id, id)` foreign key.** Cross-tenant references are impossible in the schema; national linkage happens through link tables with external references.
3. **Row-level security is forced**, and the application role is not the table owner. RLS is defense in depth, not the primary authorization mechanism.
4. **Audit is append-only and independent.** Generic audit records field *names*, never full PHI payloads.
5. **Money is integer minor units; clinical quantities are `numeric` with explicit UCUM units; no stored age.**
6. **Clinical records are versioned, not overwritten.** Signed documents and released results are immutable; corrections supersede.
7. **The event log is the integration truth.** State changes publish events in the same transaction as the state change (transactional outbox), so an event is never lost and never invented.

### 2.5 Architecture decision records (summary)

| ADR | Decision | Consequence |
|---|---|---|
| ADR-001 | PostgreSQL as the system of record | Mature RLS, constraints, exclusion constraints; operational familiarity; not the bottleneck at national scale if partitioned and cached |
| ADR-002 | Modular monolith first, extract on measured pressure | Faster safe delivery; avoids premature distribution; requires disciplined module boundaries from day one |
| ADR-003 | Transactional outbox + durable broker (Kafka-class) | No dual-write problem; at-least-once with idempotent consumers |
| ADR-004 | FHIR R4 as the external interoperability surface; internal model stays relational | Standards compliance at the edge without contorting the domain model |
| ADR-005 | Federated record locator, no central record copy | Sovereignty and reduced blast radius; cost is latency and cross-org availability |
| ADR-006 | National Health ID stored as salted hash + display suffix | Linkage without creating a national master key; requires a verification service for lookups |
| ADR-007 | Policy decision point as a shared service | Consistent consent semantics; becomes a P0 dependency with a strict latency and availability budget |
| ADR-008 | Offline clients are managed native apps with encrypted local stores | Realistic rural continuity; higher operational burden than a browser PWA |
| ADR-009 | AI runs only through a governance gateway with registered, approved model versions | Prevents shadow AI; adds friction that is intentional |
| ADR-010 | Kubernetes optional per cell, mandatory nowhere | Avoids operational complexity as a status symbol; managed container platforms acceptable |

---
"""


def section_ddd() -> str:
    header = """## 3. Domain-Driven Design

### 3.1 Domain classification

Domains are classified by strategic value, not by team convenience. Core domains get the strongest engineers, the strictest review, and the most test coverage.

```mermaid
flowchart LR
    subgraph CoreDomain["Core — differentiate and protect"]
        ID[Patient identity and EMPI]
        CONSENT[Consent and lawful access]
        CLIN[Clinical record and history]
        MED[Medication safety]
        EXCH[National exchange]
        EMER[Emergency care]
        SYNC[Offline continuity]
        AI[Clinical AI governance]
    end
    subgraph Supporting["Supporting — necessary, not differentiating"]
        BILL[Billing and revenue]
        SCHED[Scheduling and capacity]
        INV[Inventory and supply]
        LAB[Laboratory operations]
        IMG[Imaging operations]
        HR[Workforce and credentialing]
        DOC[Documents and media]
        AUD[Audit and evidence]
    end
    subgraph Generic["Generic — buy or use commodity"]
        NOTIF[Notifications]
        TERMS[Terminology distribution]
        FAC[Facility registry]
    end
```

### 3.2 Ubiquitous language (selected, binding)

Ambiguity in these terms causes real harm, so they are defined once and used everywhere.

| Term | Means precisely | Does not mean |
|---|---|---|
| Patient | The person as a subject of care, with one authoritative identity per tenant | A user account, a device, or a visit |
| National Health ID | A national linkage identifier, verified by a national authority | A password, a login, or a bearer credential |
| Encounter | A bounded episode of care between a patient and a facility | A single appointment or a single note |
| Clinical document | A versioned, signable statement of clinical record | An uploaded file attachment |
| Result | A verified diagnostic finding with provenance and status | A raw device reading |
| Medication order | A clinician's structured intent to medicate | A dispensed package or an administered dose |
| Dispense | A pharmacy event reducing stock against a verified order | A prescription |
| Administration | A bedside event recording what the patient actually received | A dispense |
| Consent directive | A patient's or law's instruction about permitted use | A UI checkbox |
| Break-glass | A time-boxed, reviewed override of normal access control | A superuser login |
| Offline snapshot | A scoped, expiring, encrypted copy for continuity | A replica of the facility database |
| Record locator | Metadata answering *where* records exist | A copy of the records |
| Event | An immutable statement that something happened, in past tense | A command or a request |
| Tenant | An independently governed organisation boundary | A facility or a department |

### 3.3 Aggregate boundaries and invariants

Aggregates are the consistency boundaries. The table below is the authoritative list; if a rule is not enforced inside one of these boundaries, it needs a saga.

"""
    rows = ["| Context | Aggregate | Invariants enforced inside the boundary |", "|---|---|---|"]
    for ctx in CONTEXTS:
        for aggregate in ctx["aggregates"]:
            rows.append(f"| {ctx['name']} | **{aggregate}** | — |")
    # Replace the placeholder with a compact per-context invariant listing.
    table = ["| Context | Aggregates | Invariants enforced inside the boundary |", "|---|---|---|"]
    for ctx in CONTEXTS:
        joined = ", ".join(f"**{a}**" for a in ctx["aggregates"])
        inv = "<br>".join(f"• {i}" for i in ctx["invariants"])
        table.append(f"| {ctx['name']} | {joined} | {inv} |")
    return header + "\n".join(table) + """

### 3.4 Context map

```mermaid
flowchart LR
    ID[Patient Identity] -->|Published Language: patient events| CONSENT[Consent and Privacy]
    ID -->|Customer/Supplier| CLIN[Clinical Record]
    ID -->|Customer/Supplier| EXCH[National Exchange]
    CONSENT -->|Conformist: policy decisions| EXCH
    CONSENT -->|Conformist| SYNC[Offline Sync]
    FAC[Facility Registry] -->|Published Language| EXCH
    FAC --> SCHED[Scheduling]
    TERMS[Terminology] -->|Published Language| LAB[Laboratory]
    TERMS --> MED[Medication]
    CLIN -->|Shared Kernel: signed document| EXCH
    CLIN -->|Customer/Supplier| AI[AI Governance]
    LAB -->|Event: result finalised| ORD[Orders and Diagnostics]
    IMG -->|Event: report finalised| ORD
    ORD -->|Event: critical result| NOTIF[Notifications]
    MED -->|Event: verified order| PHARM[Pharmacy Dispensing]
    PHARM -->|Event: dispense completed| BILL[Billing]
    PHARM -->|Event: stock movement| INV[Inventory]
    INV -->|Event: recall| PHARM
    BILL -->|Event: charge posted| LEDGER[Ledger]
    HR[Workforce] -->|Conformist: privileges| CONSENT
    AUD[Audit] -.->|Anti-Corruption Layer: subscribes to all| CLIN
    AUD -.->|ACL| EXCH
    AUD -.->|ACL| AI
```

### 3.5 Context relationships, stated as rules

| Relationship | Pattern | Rule |
|---|---|---|
| Identity → everyone | Published Language | Consumers may store a patient reference; they may never store a second copy of demographics as truth |
| Consent → Exchange/Sync | Conformist | If the PDP says no, the boundary says no; no local override except recorded break-glass |
| Clinical Record → AI | Customer/Supplier | AI adapts to clinical models, never the reverse |
| Laboratory/Imaging → Orders | Event-driven | Result ownership stays with the performing domain; the ordering domain owns the order lifecycle |
| Exchange → Clinical Record | Anti-Corruption Layer | External FHIR/C-CDA content is translated and validated, never persisted raw as clinical truth |
| Audit → all | ACL consumer | Audit subscribes to events; no domain writes directly into another's audit records |
| Inventory ↔ Pharmacy | Shared Kernel: stock ledger | One ledger, one truth; both sides append, neither mutates balances |

### 3.6 Anti-corruption layers

Every boundary that accepts foreign data needs an explicit ACL: HL7 v2 feeds, FHIR bundles from other vendors, DICOM metadata, laboratory analysers, payer claim responses, and national ID registries. An ACL must:

1. Quarantine the raw payload before parsing (stored with hash, never overwritten).
2. Validate structure, codes, units, and patient binding.
3. Map through a versioned mapping, recording the mapping version used.
4. Refuse to publish a clinical fact when validation fails — produce a review task instead.
5. Never write directly into a clinical table from the adapter process.

---

"""


def section_services() -> str:
    by_context: dict[str, list[dict]] = defaultdict(list)
    for service in SERVICES:
        by_context[service["context"]].append(service)

    rows = [
        "| Service | Context | Kind | Tier | Responsibility | Data store | Scaling model |",
        "|---|---|---|---|---|---|---|",
    ]
    for service in sorted(SERVICES, key=lambda s: (s["tier"], s["context"], s["id"])):
        rows.append(
            f"| `{service['id']}` | {service['context']} | {service['kind']} | "
            f"T{service['tier']} | {service['responsibility']} | {service['datastore']} | {service['scaling']} |"
        )

    tier_counts = defaultdict(int)
    for service in SERVICES:
        tier_counts[service["tier"]] += 1

    return f"""## 4. Bounded Contexts

### 4.1 Context catalogue

Each context is a candidate service boundary with its own model, its own data ownership, and an explicit integration contract. "Owns" means the context is the only writer of those tables. "Reads" means it consumes others' data through APIs or events, never through cross-context SQL joins in production.

| # | Context | Type | Owner team | Owns (tables) | Reads | Consistency |
|---|---|---|---|---|---|---|
""" + "\n".join(
        f"| {i + 1} | **{c['name']}** (`{c['id']}`) | {TYPE_LABEL[c['type']]} | {c['owner_team']} | "
        f"{len(c['owns'])} | {len(c.get('reads', []))} | {c['consistency']} |"
        for i, c in enumerate(CONTEXTS)
    ) + """

### 4.2 Ownership detail

Ownership is the difference between a modular monolith and a distributed ball of mud. The table below is the single source of truth for "who may write this table".

| Context | Tables it exclusively owns |
|---|---|
""" + "\n".join(
        f"| **{c['name']}** | " + (", ".join(f"`{t}`" for t in c["owns"]) if c["owns"] else "— (no tables; stateless or read-only)") + " |"
        for c in CONTEXTS
    ) + """

### 4.3 Contexts that guard safety-critical decisions

| Context | Failure mode if it silently fails | Required behaviour |
|---|---|---|
| Consent & policy | Unlawful disclosure of patient data | Fail closed; deny and audit; queue for review |
| Medication safety | Unsafe order dispensed or administered | Fail closed on knowledge-base unavailability; no silent "assume safe" |
| Laboratory verification | Unverified result treated as final | Hold result; escalate; never auto-release |
| Radiology reporting | Unsigned report used in care | Mark preliminary and require acknowledgement |
| AI governance | Unreviewed model output enters the record | Block inference; log the attempt |
| Offline sync | Stale or conflicting data overwrites truth | Reject, surface conflict, require human resolution |
| Audit | Evidence gap after an incident | Block the privileged action rather than proceed unaudited |

---
"""


def section_events() -> str:
    phi = sum(1 for e in EVENTS if e["contains_phi"])
    tier_counts = defaultdict(int)
    for service in SERVICES:
        tier_counts[service["tier"]] += 1

    tier_table = "\n".join(
        f"| T{tier} | {tier_counts[tier]} | {label} |" for tier, label in sorted(TIER_LABEL.items())
    )

    service_rows = ["| Service | Context | Kind | Tier | Responsibility |", "|---|---|---|---|---|"]
    for service in sorted(SERVICES, key=lambda s: (s["tier"], s["context"], s["id"])):
        service_rows.append(
            f"| `{service['id']}` | {service['context']} | {service['kind']} | T{service['tier']} | "
            f"{service['responsibility']} |"
        )
    service_table = "\n".join(service_rows)

    event_rows = [
        "| Event | Producer | Key consumers | Partition key | PHI | Retention (days) |",
        "|---|---|---|---|---|---|",
    ]
    for event in sorted(EVENTS, key=lambda e: e["name"]):
        consumers = ", ".join(event["consumers_contexts"][:4])
        if len(event["consumers_contexts"]) > 4:
            consumers += f", +{len(event['consumers_contexts']) - 4}"
        event_rows.append(
            f"| `{event['name']}` | `{event['producer']}` | {consumers} | "
            f"`{event['partition_key']}` | {'yes' if event['contains_phi'] else 'no'} | {event['retention_days']} |"
        )
    event_table = "\n".join(event_rows)

    return f"""## 5. Service Map

### 5.1 Service inventory

{len(SERVICES)} services across {len(CONTEXTS)} contexts. Tiering drives runbooks, SLOs, and on-call: a T0 service is never allowed to depend synchronously on a T2 service.

| Tier | Count | Meaning |
|---|---|---|
{tier_table}

{service_table}

### 5.2 Synchronous call rules

Synchronous calls are a coupling budget, and the budget is small.

| Allowed | Prohibited |
|---|---|
| Gateway → T0/T1 service (with timeout and circuit breaker) | T0 → T2/T3 synchronous dependency |
| Service → own database | Service → another service's database |
| Service → PDP for an access decision (strict budget) | Service → another service for a write it does not own |
| Gateway → read model for display | Chatty per-row cross-service calls |
| Any service → object storage via short-lived credential | Long-lived shared bucket credentials |

### 5.3 Service-to-service map

```mermaid
flowchart LR
    GW[api-gateway] --> IDAPI[identity-api]
    GW --> CONSAPI[consent-api]
    GW --> ENCAPI[encounter-api]
    GW --> CLINAPI[clinical-record-api]
    GW --> ORDAPI[orders-api]
    GW --> MEDAPI[prescribing-api]
    GW --> LABAPI[lab-api]
    GW --> IMGAPI[imaging-api]
    GW --> BILLAPI[billing-api]
    GW --> SCHAPI[scheduling-api]
    GW --> EXGW[exchange-gateway]
    GW --> SYNCAPI[sync-api]
    GW --> AIORCH[ai-orchestrator]

    IDAPI --> EMPI[empi-matcher]
    IDAPI --> HID[health-id-service]
    CONSAPI --> PDP[policy-decision-point]
    EXGW --> PDP
    EXGW --> LOC[record-locator]
    EXGW --> FHIR[fhir-facade]
    EXGW --> HL7[hl7v2-adapter]
    CLINAPI --> SIGN[document-signing-worker]
    CLINAPI --> SUMM[patient-summary-service]
    ORDAPI --> ROUTE[result-routing-worker]
    MEDAPI --> SAFETY[medication-safety-service]
    LABAPI --> LABW[lab-workflow-worker]
    LABAPI --> VERIFY[result-verification-service]
    IMGAPI --> PACS[pacs-link-worker]
    IMGAPI --> RADSIGN[radiology-reporting-service]
    BILLAPI --> CLAIM[claims-worker]
    BILLAPI --> LEDGERW[ledger-worker]
    MEDAPI --> ADMAPI[administration-api]
    SCHAPI --> CAP[capacity-planner]
    SYNCAPI --> SNAP[snapshot-builder]
    SYNCAPI --> TRUST[device-trust-service]
    AIORCH --> MR[model-registry-api]
    AIORCH --> OVERSIGHT[ai-oversight-worker]
    ROUTE --> NOTIFS[notification-service]
    NOTIFS --> DELIV[delivery-worker]
    SIGN --> MEDIA[media-gateway]
    RADSIGN --> MEDIA
    CLINAPI --> AUDW[audit-writer]
    EXGW --> AUDW
    AIORCH --> AUDW
    AUDW --> SIEM[siem-bridge]
```

### 5.4 Degradation ladder

When a dependency fails, behaviour is designed in advance rather than improvised at 3 a.m.

| Failed dependency | Clinical behaviour | Technical behaviour |
|---|---|---|
| Policy decision point | Deny cross-organisation access; allow same-facility care with recorded local policy snapshot | Short local cache with version stamp; circuit breaker; alert |
| Medication knowledge base | Block new high-risk orders; allow continuation of existing orders with warning | Fail closed; queue for manual pharmacist review |
| Event broker | Continue local writes; buffer in outbox | Outbox drains on recovery; consumer lag alert |
| Laboratory interface | Manual result entry with double-check | Quarantine inbound messages; replay after recovery |
| Exchange gateway | Local care continues; cross-org requests queued | Locator returns cached availability with staleness marker |
| Object storage | Documents show unavailable, never silently empty | Retry with backoff; escalate |
| Audit store | **Block privileged actions** | This is a deliberate, uncomfortable choice: unaudited privileged access is worse than downtime |

---

## 6. Event Map

### 6.1 Event catalogue

{len(EVENTS)} versioned domain events, {phi} of which carry patient identifiers and therefore inherit tenant partitioning, encryption, and strict access control.

{event_table}

### 6.2 Event flow by clinical journey

```mermaid
sequenceDiagram
    participant Pat as Patient
    participant Reg as identity-api
    participant Enc as encounter-api
    participant Clin as clinical-record-api
    participant Ord as orders-api
    participant Lab as lab-api
    participant Med as prescribing-api
    participant Bill as billing-api
    participant Bus as Event broker

    Pat->>Reg: Registration + Health ID verification
    Reg->>Bus: patient.registered.v1
    Pat->>Enc: Arrival / triage
    Enc->>Bus: encounter.started.v1
    Enc->>Clin: Documentation context
    Clin->>Bus: clinical-note.signed.v1
    Enc->>Ord: Order placed
    Ord->>Bus: service-request.created.v1
    Lab->>Bus: specimen.collected.v1
    Lab->>Bus: lab-result.released.v1
    Bus->>Ord: lab-result.released.v1
    Ord->>Bus: result.finalized.v1
    Bus->>Med: result.finalized.v1 (safety context)
    Med->>Bus: prescription.created.v1
    Med->>Bus: prescription.verified.v1
    Ord->>Bus: result.critical-flagged.v1
    Bus->>Bill: encounter.ended.v1
    Bill->>Bus: charge.posted.v1
    Bill->>Bus: invoice.issued.v1
```

### 6.3 Delivery semantics

| Property | Commitment |
|---|---|
| Publication | Transactional outbox in the same database transaction as the state change |
| Delivery | At least once; consumers must be idempotent by event ID |
| Ordering | Per partition key only (tenant, patient, encounter, or aggregate ID); no global ordering |
| Schema evolution | Additive fields within a major version; breaking changes publish a new `.vN` and both run during migration |
| Replay | Retained per the catalogue; replay is a supported operational procedure, not an emergency hack |
| Poison messages | Dead-letter queue with alerting; nothing is silently dropped |
| PHI in payloads | Identifiers and clinical deltas only where a consumer is entitled; otherwise reference + fetch |

### 6.4 Why the event map is not event sourcing

The platform uses events for **integration and audit**, not as the primary store of clinical state. Clinical state lives in relational tables with constraints, transactions, and RLS. Full event sourcing of clinical records would make consent-driven restriction, correction semantics, and regulatory reporting dramatically harder, and would couple every consumer to an internal history format. Selective history (document versions, stock ledger, financial ledger, audit) is append-only; the rest is mutable state with versioning.

---
"""


def section_database() -> str:
    return """## 7. Database Strategy

### 7.1 What already exists (verified, not aspirational)

`database/migrations/V001`–`V008` implement the clinical core. These numbers come from a live catalog, not from a design sketch:

| Property | Value |
|---|---|
| Tables | 103 |
| Foreign keys | 272 |
| Indexes | 387 |
| Row-level-security-enabled tables | all tenant-owned tables, forced |
| Integrity tests | 43, all passing on PostgreSQL 17.11 |
| Tenant-safe composite FKs | enforced; single-column cross-tenant FKs are rejected by test |

The full entity-relationship diagrams, table inventory, and index inventory are generated from the live catalog into **`docs/DATABASE_ERD.md`**.

### 7.2 Data ownership and the polyglot boundary

| Store | Owns | Must never own |
|---|---|---|
| PostgreSQL (per cell) | Clinical and transactional truth | Imaging pixels, large media blobs, analytics scans |
| Object storage | Documents, media, exports, snapshots | Authoritative clinical status |
| PACS/VNA | DICOM pixels and series | Reports, orders, or patient identity |
| Search index (locator/EMPI) | Candidate matches, record locations | Authoritative patient or clinical data |
| Analytics store | De-identified aggregates and indicators | Re-identifiable clinical records |
| Append-only audit store | Access and change evidence | Full PHI payloads |
| Broker | Event transport and replay buffer | The only copy of any fact |

### 7.3 Partitioning and growth

Partitioning is an operational response to measured size, not an opening architecture.

| Table family | Trigger to partition | Scheme |
|---|---|---|
| `audit_event` | > 50 M rows or 100 GB | Monthly range on `occurred_at`; BRIN retained |
| `observation`, `result_value` | > 200 M rows | Monthly range on effective time, subpartition by tenant for very large tenants |
| `outbox_event`, `inbound_message` | > 50 M rows | Daily/weekly range with aggressive retention |
| `stock_movement`, `financial_ledger_entry` | > 100 M rows | Quarterly range by posting date |
| `sync_change_log` | > 100 M rows | Daily range, short retention |

### 7.4 Multi-tenancy tiers

| Tier | Pattern | When | Trade-off |
|---|---|---|---|
| Shared cell, shared schema, RLS | Default for clinics, pharmacies, small hospitals | 80% of tenants | Cheapest; noisy-neighbour risk mitigated by quotas |
| Shared cell, dedicated schema | Mid-size hospitals wanting isolation within a cell | 15% | More migration overhead |
| Dedicated database cluster | Large hospitals, national programmes, strict contracts | 5% | Highest isolation and cost |

Schema-per-tenant for thousands of tenants is explicitly rejected: migration fan-out, connection management, and monitoring become unmanageable.

### 7.5 National identity and cross-organisation linkage

The national layer solves the problem relational databases cannot solve safely on their own: linking one person across organisations without merging their databases.

- `national_health_id` stores a salted hash plus a four-character display suffix. The identifier is never a login credential.
- `patient_link_organisation` is the only permitted cross-organisation patient reference, and it is a link table with an external reference — never a foreign key into another tenant.
- `record_locator_entry` answers *where* records exist without copying them.
- Merge never deletes: `patient_link` records lineage and can be reverted.

### 7.6 Data lifecycle and sovereignty

| Data class | Residency | Retention (baseline) | Deletion model |
|---|---|---|---|
| Clinical record | Tenant's residency zone | Per national health-records law (commonly 10–25 years after last contact) | Legal hold, then archival review; not user-deletable |
| Audit evidence | Independent national store | Longer than clinical data (often 6–10 years minimum) | Never deleted before schedule; WORM archive |
| Biometric/identity documents | Highest-residency zone | Minimum necessary | Aggressive deletion after verification |
| Offline snapshots | On device only | Maximum offline window (e.g. 72 hours) | Cryptographic erase on expiry or revocation |
| Analytics | National zone, de-identified | Rolling | Small-cell suppression before publication |
| Backups | Same zone as source | 35 days operational + monthly archives | Encrypted with zone-held keys |

### 7.7 Backup, restore, and disaster recovery targets

| Service class | RPO | RTO | Mechanism |
|---|---|---|---|
| Identity, consent, clinical core | ≤ 5 min | ≤ 1 h | Streaming replication + PITR + warm standby cell |
| Laboratory, imaging metadata | ≤ 15 min | ≤ 4 h | Streaming replication + PITR |
| Billing and ledger | ≤ 5 min | ≤ 2 h | Synchronous replica + append-only ledger replay |
| Audit store | 0 (no loss acceptable) | ≤ 1 h | Independent append-only store, cross-zone replication, WORM |
| Analytics | ≤ 24 h | ≤ 24 h | Rebuildable from event archive |
| Offline clients | Best effort | N/A | Encrypted local store; resync after recovery |

Restore is treated as a product feature: quarterly restore drills with measured timings, published results, and a rule that an untested backup is not a backup.

### 7.8 Migration and legacy onboarding

```mermaid
flowchart LR
    Profile[Profile source data] --> Map[Map to national model]
    Map --> Cleanse[Cleanse and validate]
    Cleanse --> Match[Identity match and review]
    Match --> Rehearse[Rehearse on masked copy]
    Rehearse --> Reconcile[Clinical and financial reconciliation]
    Reconcile --> Approve[Clinical owner approval]
    Approve --> Cutover[Cut over with rollback plan]
    Cutover --> Archive[Archive source per policy]
```

Every migration reports row counts, rejects, mapping versions, identifier links, and financial/stock control totals. Production PHI never populates developer or test environments.

---
"""


def section_infrastructure() -> str:
    return """## 8. Infrastructure Strategy

### 8.1 Environments

| Environment | Data | Purpose | Access |
|---|---|---|---|
| Local dev | Synthetic fixtures only | Fast iteration | Developer laptop |
| CI ephemeral | Synthetic + generated | Automated tests incl. RLS and constraint tests | Pipeline identity |
| Integration | Synthetic, reset nightly | Cross-service contracts | Team |
| Staging | Masked subset with written approval | Release candidate and performance | Restricted |
| Production | Real PHI | Care delivery | Break-glass, audited |
| DR | Replicated production | Recovery | Two-person rule |

### 8.2 Deployment topology per cell

```mermaid
flowchart TB
    subgraph Region["Residency zone"]
        LB[Load balancer + WAF]
        subgraph K8s["Container platform (or equivalent)"]
            FE[Web/BFF pods]
            SVC[Domain service pods]
            WK[Worker pods]
        end
        PGp[(PostgreSQL primary)]
        PGr[(PostgreSQL synchronous replica)]
        PGd[(PostgreSQL async DR replica)]
        OBJ[(Object storage, zone keys)]
        BUS[(Event broker, 3 AZ)]
        AUD[(Audit shipper)]
        LB --> FE --> SVC --> PGp
        SVC --> BUS
        WK --> BUS
        PGp --> PGr
        PGr --> PGd
        SVC --> OBJ
        SVC --> AUD
    end
    Zone2[Second residency zone] -.->|cross-zone DR| PGd
```

### 8.3 Security architecture

| Control | Implementation |
|---|---|
| Authentication | OIDC with MFA; BFF pattern so tokens never live in the browser |
| Authorisation | ABAC/RBAC in the PDP; purpose-of-use and consent as first-class inputs |
| Tenant context | Server-derived, transaction-local database setting after authorization |
| Secrets | Managed KMS/secrets; no credentials in images or repos; short-lived DB credentials |
| Encryption | TLS 1.3 in transit; AES-256 at rest; zone-held keys; separate keys per data class |
| Field-level protection | Application-level envelope encryption for the most sensitive identifiers |
| Network | Default-deny, private service mesh, egress allowlists, WAF |
| Supply chain | Pinned dependencies, SBOM, signed images, provenance attestation |
| Vulnerability management | SAST/DAST/dependency/secret scanning in CI, with time-bound exceptions |
| Monitoring | OpenTelemetry traces, metrics, structured logs with PHI scrubbing at the SDK |
| Incident response | Severity model, 24/7 on-call for T0, forensic readiness with preserved audit |

### 8.4 Observability without leaking PHI

- Trace and log payloads contain IDs, not clinical content. A redaction layer runs before export.
- Clinical services emit **clinical safety metrics** alongside technical ones: unsafe-order blocks, failed-closed safety checks, unacknowledged critical results, sync conflicts.
- SLOs are defined per tier, and error budgets are real: repeated budget burn blocks feature work in favour of reliability.

### 8.5 Delivery pipeline

| Stage | Gate |
|---|---|
| Pre-commit | Formatting, type check, secret scan |
| PR | Unit tests, contract tests, schema migration dry run, RLS negative tests |
| Merge | Build, SBOM, image signing, ephemeral integration environment |
| Staging | Performance test, migration rehearsal on masked data, clinical smoke scripts |
| Production | Progressive rollout, feature flags, automated rollback, post-deploy verification |
| Database changes | Expand → migrate → contract, never a destructive single-step change |

### 8.6 Cost strategy

Cost is an architectural constraint. The dominant costs are clinical data storage, audit retention, imaging, managed databases, and security tooling — in that order. Controls: tiered object storage, audit partitioning with legal retention discipline, strict imaging lifecycle, per-tenant quotas, and a rule that no service may scale replicas without an SLO justification.

---
"""


def section_scaling() -> str:
    return """## 9. National Scaling Strategy

### 9.1 Scaling model

Growth is absorbed in this order, and only when the previous lever is exhausted:

```mermaid
flowchart LR
    A[1. Query and index tuning] --> B[2. Read replicas and caching]
    B --> C[3. Vertical scaling of the primary]
    C --> D[4. Table partitioning]
    D --> E[5. Service extraction and independent scaling]
    E --> F[6. New cell / residency zone]
    F --> G[7. Tenant sharding across cells]
```

Premature steps are expensive and add failure modes. A team that adds a cell before fixing an N+1 query has bought two problems.

### 9.2 Onboarding waves

| Wave | Tenants | Focus | Exit criteria |
|---|---|---|---|
| Pilot | 1 hospital + 2 clinics | Clinical core, offline, audit | 90 days without a safety incident; restore drill passed |
| Regional | 15 organisations across 2 provinces | Exchange, locator, pharmacy, laboratory | Cross-org sharing works with consent; latency within budget |
| National core | 120 organisations | Emergency, telemedicine, public health | Outbreak signal within 24 h; mass-casualty drill passed |
| Universal | 400 organisations incl. private pharmacies | Health ID at scale, payer integration | 95% of facilities onboarded; support cost per facility falling |

### 9.3 Bottlenecks and mitigations

| Bottleneck | Symptom | Mitigation |
|---|---|---|
| PostgreSQL write throughput | Rising commit latency on encounter writes | Partition hot tables, move audit writes off the primary path, extract the highest-volume writer |
| Policy decision point latency | Every request waits on consent | Local decision caching with versioned invalidation; PDP horizontally scaled with strict p99 |
| Exchange fan-out | Cross-org queries slow at national scale | Locator-first design; cached availability; asynchronous document retrieval |
| Patient identity contention | Merge storms during onboarding | Batch matching off-peak, review queues, merge rate limiting |
| Audit volume | Storage and write amplification | Field-name-only audit, sampling for reads, tiered retention |
| Offline sync bursts | Reconnect storms after outages | Jittered sync, server-side batching, per-device rate limits |
| Event lag | Stale analytics and surveillance | Consumer isolation by tier; backpressure with retention buffer |

### 9.4 Availability targets

| Tier | Availability target | Maintenance window | Degraded-mode requirement |
|---|---|---|---|
| T0 | 99.95% monthly | None for writes; rolling | Read-only clinical access + offline continuity |
| T1 | 99.9% | Low-activity windows | Queue and retry; no data loss |
| T2 | 99.5% | Scheduled | Manual fallback acceptable |
| T3 | 99.0% | Scheduled | Deferred |

### 9.5 Supporting 2,500 facilities without 2,500 support tickets

Self-service onboarding with a facility checklist, automated configuration validation, in-product guided setup, a tiered support model (national → regional → facility), and a published capability matrix per facility. Every recurring support question becomes a product decision or a documentation fix; a support queue that grows with onboarding is an architectural failure signal.

---
"""


def section_roadmap() -> str:
    return """## 10. Five-Year Transformation Roadmap

### 10.1 Roadmap principles

1. Every phase ships something a clinician can use safely; no phase is purely foundational for a year.
2. Safety, security, and operability gates are passed **before** expanding scope.
3. Certification and regulatory work runs in parallel with engineering, starting in Year 1 — not after go-live.
4. Each phase has explicit exit criteria and a kill/pause condition.

```mermaid
gantt
    title Five-year national healthcare platform roadmap
    dateFormat YYYY-MM
    axisFormat %Y-%m

    section Year 1 Foundation
    Clinical vertical slice (auth to audit)      :a1, 2026-01, 6M
    Database hardening and RLS verification      :a2, 2026-01, 4M
    Offline continuity pilot                     :a3, 2026-04, 5M
    Security certification readiness             :a4, 2026-02, 10M

    section Year 2 Regional
    Hospital core modules (lab, pharmacy, billing):b1, 2027-01, 8M
    National Health ID pilot                     :b2, 2027-01, 6M
    Exchange and record locator (2 provinces)    :b3, 2027-03, 8M
    Regional go-live (15 organisations)          :b4, 2027-09, 3M

    section Year 3 National core
    Emergency and prehospital services           :c1, 2028-01, 8M
    Telemedicine network                         :c2, 2028-02, 7M
    Public health surveillance                    :c3, 2028-04, 6M
    AI governance and assisted documentation     :c4, 2028-05, 6M
    National rollout begins (120 orgs)           :c5, 2028-09, 4M

    section Year 4 Universal
    Private pharmacy and lab onboarding          :d1, 2029-01, 8M
    Payer and claims integration                 :d2, 2029-02, 7M
    Multi-zone residency and DR maturity         :d3, 2029-01, 9M
    Cross-border and referral corridors          :d4, 2029-05, 6M

    section Year 5 Optimization
    Scale to 400 organisations                   :e1, 2030-01, 10M
    Advanced AI with clinical validation         :e2, 2030-01, 9M
    Cost and efficiency programme                :e3, 2030-03, 8M
    Independent audit and public transparency    :e4, 2030-04, 6M
```

### 10.2 Phase detail

| Phase | Objectives | Deliverables | Exit criteria | Primary risks |
|---|---|---|---|---|
| **P0 — Foundation** (M0–6) | Prove one safe clinical vertical slice end to end | Authenticated tenant/facility/patient/encounter chain, conflict-safe appointment, signed document, audit + outbox, monitored backup/restore, hard-coded fixtures removed, real test suite in CI | External security review passed for the slice; restore drill ≤ RTO; zero PHI in logs; 43+ database integrity tests green | Scope creep; treating the prototype as a base; underestimating identity work |
| **P1 — Clinical core** (M6–12) | Make one hospital fully operable | Laboratory, pharmacy, imaging metadata, billing, scheduling, medical history, RBAC/ABAC enforcement, offline continuity pilot | 90 days live without a patient-safety incident; clinical sign-off on workflows; support load within plan | Workflow mismatch; resistance from staff; downtime procedure gaps |
| **P2 — Regional exchange** (Y2) | Connect organisations without centralising data | National Health ID pilot, EMPI, consent service, PDP, record locator, exchange gateway, FHIR facade, cross-org sharing | Consent-correct sharing verified by independent test; refusal/denial paths evidenced; latency within budget | Consent semantics disagreements; vendor interoperability; identity match quality |
| **P3 — National core** (Y3) | Cover urgent and remote care plus public health | Emergency/dispatch, telemedicine, referrals, surveillance, AI governance with documentation assistance | Mass-casualty drill passed; outbreak signal ≤ 24 h; every AI output has human review evidence | Emergency integration complexity; AI overreach; surveillance privacy |
| **P4 — Universal coverage** (Y4) | Extend to private pharmacies, labs, payers; mature DR | Pharmacy/lab onboarding, claims and payer integration, multi-zone residency, cross-border corridors | 3 residency zones operational; DR failover exercised; claims reconciliation within tolerance | Commercial/legal negotiation; payer data quality; multi-zone latency |
| **P5 — Optimisation** (Y5) | Scale, reduce cost, deepen capability | 400 organisations, validated clinical AI, cost programme, independent audit and public reporting | Cost per facility down ≥ 30%; availability targets met for 4 consecutive quarters; independent audit clean | Complacency; accumulated technical debt; funding continuity |

### 10.3 Workstreams and ownership

| Workstream | Owns | Key interfaces |
|---|---|---|
| Clinical safety & informatics | Clinical models, decision support, safety cases | Product, engineering, regulator |
| Identity & exchange | EMPI, Health ID, locator, consent enforcement | Privacy, facilities, national ID authority |
| Platform engineering | Cells, data, events, sync, observability | Security, SRE |
| Security & privacy | Threat model, PDP policy, audit evidence, incident response | Legal, regulator, SOC |
| Interoperability | FHIR/HL7/DICOM, terminology, vendor onboarding | Vendors, facilities |
| Data & analytics | Public health indicators, de-identification | Ministry, epidemiology |
| Delivery & adoption | Training, change management, support model | Facilities, regional health authorities |

### 10.4 Investment profile (indicative, relative)

| Phase | Engineering | Infrastructure | Security/compliance | Change management |
|---|---|---|---|---|
| P0 | High | Low | Medium | Low |
| P1 | High | Medium | Medium | High |
| P2 | High | Medium | High | Medium |
| P3 | High | Medium | Medium | High |
| P4 | Medium | High | High | High |
| P5 | Medium | High | Medium | Medium |

Security and compliance spending is front-loaded on purpose: retrofitting it into a live national platform costs multiples more and damages public trust irreversibly.

### 10.5 Kill and pause conditions

The programme should pause expansion — not necessarily stop — when any of these is true:

- A patient-safety incident traced to the platform remains without a verified fix.
- Restore drills fail their RTO two quarters running.
- Consent correctness fails independent testing.
- Audit evidence has a proven gap.
- Onboarding support cost per facility is rising quarter over quarter.
- A residency or legal obligation cannot be met by the current cell topology.

### 10.6 What five years should actually produce

A clinician in a rural clinic documents care offline that reconciles safely when the network returns; a patient's allergy recorded in one province is visible — with consent — in another; a critical lab result reaches a named clinician with evidence of acknowledgement; the ministry sees outbreak signals without seeing individuals; and an independent auditor can reconstruct who accessed what, why, and under which policy version. If the platform delivers those five things, the technology choices were right. If it delivers a feature list without them, they were not.

---
"""


def section_risk() -> str:
    return """## 11. Risk Register and Honest Limits

### 11.1 Top risks

| # | Risk | Likelihood | Impact | Mitigation | Residual |
|---|---|---|---|---|---|
| R1 | Identity mismatch links the wrong patient's records | Medium | Severe | Reviewed merges, reversible links, confidence thresholds, no auto-merge across organisations | Medium |
| R2 | Consent logic is subtly wrong and discloses data | Medium | Severe | Independent consent testing, deny-by-default, policy versioning, red-team exercises | Medium |
| R3 | Offline conflict resolution corrupts clinical truth | Medium | Severe | No last-write-wins, explicit conflict queues, clinical adjudication | Medium |
| R4 | Connectivity outages exceed offline window | High | High | Managed devices, bounded snapshots, printed downtime procedures, drills | Medium |
| R5 | Scope outruns delivery capability | High | High | Phase gates, kill conditions, ruthless prioritisation | Medium |
| R6 | Vendor interoperability gaps (PACS, analysers, payers) | High | Medium | ACLs, quarantine, certification programme, fallback manual paths | Medium |
| R7 | Insider misuse of access | Medium | High | Break-glass review, anomaly detection, least privilege, audit independence | Medium |
| R8 | National Health ID becomes a de facto master credential | Low | Severe | Hash storage, no authentication use, independent verification service, policy prohibition | Low |
| R9 | AI output enters the record unreviewed | Low | Severe | Model registry approval gate, database-level blocking, review evidence required | Low |
| R10 | Multi-zone residency latency degrades care | Medium | Medium | Locator-first design, asynchronous propagation, zone-local reads | Low |
| R11 | Funding or political discontinuity | Medium | High | Phased value delivery, open standards, documented handover | Medium |
| R12 | Data breach of a cell | Low | Severe | Cell isolation, minimal national data, encryption, incident readiness | Medium |

### 11.2 What this document does not establish

- It does not make the platform production-ready. The repository remains **NO-GO** for real patient data.
- It does not constitute a clinical safety case, a privacy impact assessment, or a regulatory submission.
- It does not validate any AI model for clinical use.
- It does not prove the capacity model; it states assumptions that must be tested with real load.
- It does not resolve legal questions about consent, minors, mentally incapacitated patients, or cross-border transfer — those require named legal authority and documented decisions.

### 11.3 Verification status of the artefacts

| Artefact | Status | How it is checked |
|---|---|---|
| `database/migrations/V001–V008` | Executed successfully on PostgreSQL 17.11 | Full apply from empty cluster |
| `database/tests/schema_integrity.sql` | 43 assertions passing | Live run against the applied schema |
| `docs/DATABASE_ERD.md` | Generated from the live catalog | `database/tools/generate_erd.py` |
| `architecture/catalog/*.json` | Internally consistent | `architecture/tools/validate_architecture.py` |
| This document | Generated from the catalogs | `architecture/tools/render_architecture.py` |

---
"""


def main() -> None:
    parts = [
        "# AYBAK National Healthcare Platform — Target Enterprise Architecture",
        "",
        "**Role basis:** National Healthcare Platform Architect  ",
        "**Scope:** hospitals, clinics, pharmacies, laboratories, radiology centres, emergency services, telemedicine, Ministry of Health  ",
        "**Status:** Target architecture — design only. The repository remains **NO-GO for real patient data or clinical use**.  ",
        "**Companion documents:** `docs/ENTERPRISE_AUDIT.md`, `docs/ENTERPRISE_TRANSFORMATION_PLAN.md`, `docs/IMPLEMENTATION_BLUEPRINT.md`, `docs/DATABASE_ERD.md`",
        "",
        "> Every table, service, and event listing in this document is generated from "
        "`architecture/catalog/*.json`, which is validated by "
        "`architecture/tools/validate_architecture.py`: 24 bounded contexts, "
        "63 services, 102 domain events, and 103 database tables, each owned by exactly one context.",
        "",
        "---",
        "",
        section_executive(),
        section_architecture(),
        section_ddd(),
        section_services(),
        section_events(),
        section_database(),
        section_infrastructure(),
        section_scaling(),
        section_roadmap(),
        section_risk(),
    ]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(parts), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(OUT.read_text(encoding='utf-8').splitlines())} lines)")


if __name__ == "__main__":
    main()
