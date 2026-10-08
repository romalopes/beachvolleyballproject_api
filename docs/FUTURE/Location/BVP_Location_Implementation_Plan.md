# BeachVolleyballProject — Location Architecture & Implementation Plan

**Date:** 8 October 2026  
**Projects:** `romalopes/beachvolleyballproject_api` (Rails) and `romalopes/beachvolleyballproject` (React/Vite)  
**Status:** Implementation proposal; repository details must be verified before migrations.  
**Scope:** Locations for organisations, independent groups, trainings and tournaments, with geocoding, curation, deduplication, migration and operational documentation.

## 1. Goals and architectural decisions

- Create a reusable `Location` domain entity representing a beach, sports venue, park or other physical place. Do not collapse it into `Address` merely to save a table.
- Reuse the existing `Address` model **if present and appropriate**; otherwise assess whether a small structured address component is warranted. Avoid duplicate address systems.
- Store `latitude` and `longitude` on `Location`, because a beach's meaningful pin can differ from its postal address. Use PostgreSQL decimal/numeric with adequate precision (e.g. 10,7), validate latitude −90..90 and longitude −180..180.
- `Organisation.default_location_id` and `Group.default_location_id` are optional defaults. Independent groups may have their own default. Organisation-owned groups may override their organisation's default.
- `Training.location_id` and `Tournament.location_id` represent **persisted actual venues**, not dynamically computed defaults; each also has optional `location_detail` (e.g. “Court 1”, “North end”).
- Start with a single location per tournament; defer multi-venue tournaments and structured courts.
- Keep PostGIS optional for later. Rails Geocoder provides geocoding and basic nearby search, not an authoritative place identity or an autocomplete service.
- Preserve historical references: archive locations instead of deleting referenced rows; foreign keys use `ON DELETE RESTRICT`/equivalent.
- Do not run external geocoding in validations, migrations, seeds or synchronous normal request paths.
- Public Nominatim: identify application with valid User-Agent/contact, obey maximum 1 request/second, attribution, caching requirements and no public-endpoint autocomplete. Check current policy before deployment.
- Provider terms differ: verify retention, display, caching and storage terms before using Google Places/Geocoding or other commercial APIs. Do not assume permanently storing provider coordinates is permitted.

## 2. Proposed domain model

```text
Address (existing, optional)
    ^
    | belongs_to :address, optional: true
Location
    |-- has_many :location_aliases
    |-- has_many :location_external_references [optional, deferred]
    |-- belongs_to :verified_by, class_name: 'User' [verify auth model]
    |-- has_many :trainings
    |-- has_many :tournaments
    |-- has_many :organisations, foreign_key: :default_location_id
    `-- has_many :groups, foreign_key: :default_location_id

Organisation.default_location_id -> Location
Group.default_location_id        -> Location
Training.location_id             -> Location
Training.location_detail         -> string
Tournament.location_id           -> Location
Tournament.location_detail       -> string
```

### Location columns (proposed)

| Column | Type | Notes |
|---|---|---|
| `name` | string, required | Human-friendly canonical name |
| `normalized_name` | string, required | Unicode-aware normalized searchable key |
| `location_type` | string | `beach`, `sports_venue`, `park`, `indoor`, `other`; string enum or validated inclusion |
| `address_id` | FK nullable | Reuse existing Address when appropriate |
| `formatted_address` | string nullable | Provider/display suggestion, not necessarily postal address |
| `latitude`, `longitude` | decimal(10,7), nullable | Exact verified/manual or geocoded pin; both present or both absent |
| `timezone` | string | IANA identifier, e.g. `Australia/Sydney` |
| `geocoding_provider` | string nullable | e.g. `nominatim`; provenance, not venue owner |
| `provider_place_id` | string nullable | Provider-specific, not globally stable |
| `geocoding_status` | string | `pending`, `geocoded`, `failed`, `manual` |
| `geocoded_at` | datetime nullable | Last successful lookup |
| `verified_at` | datetime nullable | Separate from geocoding success |
| `verified_by_id` | FK nullable | Match project's actual User/Account authorization model |
| `description`, `notes` | text nullable | Public description vs internal curator notes |
| `active` | boolean, default true | Archived records remain referenced |
| `created_by_id` | FK nullable | Provenance; match existing identity model |
| `merged_into_id` | FK nullable | Optional tombstone for merged records |
| timestamps | datetime | Standard Rails timestamps |

**Important:** `geocoding_status=manual` is not a substitute for verification. A manual pin can be unverified; a geocoded pin can be verified. Consider storing a separate `coordinate_source` (`manual`, `seed`, `geocoder`) if clearer than overloading status.

### Aliases

`LocationAlias(location_id, name, normalized_name)` with indexes on `location_id` and normalized name. An alias may be shared by different places in different suburbs; do not impose global uniqueness on alias names.

### Indexes and constraints

- Unique `(geocoding_provider, provider_place_id)` **only when both values are non-null**, subject to provider licensing and actual ID semantics.
- Scoped index for `(normalized_name, locality scope)` after confirming Address schema. Do not assume `suburb` is on Location or blindly create a unique `(name, suburb)` index.
- Index latitude/longitude for basic lookup as appropriate; PostGIS geography/GiST later if necessary.
- Check constraint: both coordinates null or both non-null; bounds checks; valid IANA timezone at application layer.
- Index all FK columns and `active` where useful.
- Duplicate detection must warn, not automatically merge based only on name or 200 m distance.

## 3. Inheritance and event behavior

When creating a training, resolve its proposed default in this order:

1. Explicitly chosen location.
2. Group's `default_location_id` if present.
3. Group's parent organisation's `default_location_id` if applicable.
4. Direct training organisation's `default_location_id` if applicable.
5. Blank: require manual selection when workflow demands it.

Persist `training.location_id` at creation. Changing an organisation or group default must **not** rewrite existing trainings or tournaments. Provide an explicit “apply new default to selected future events” action only if separately approved.

For tournaments, prefill from organising organisation/group if available but persist independently. `location_detail` is free text with length validation and no court entity yet.

## 4. Permission model

Use existing authorization infrastructure; do not introduce parallel role checks. Map exact abilities to current role/permission implementation during audit.

| Capability | Guest/reader | Coach | Curator | Admin |
|---|---|---|---|---|
| Read active locations | Yes, subject to event visibility | Yes | Yes | Yes |
| Choose active location for an event they may edit | No | Yes | Yes | Yes |
| Propose location | No or authenticated users, product decision | Yes | Yes | Yes |
| Edit own pending proposal | No | Yes, before verification | Yes | Yes |
| Verify or correct canonical pin | No | No | Yes | Yes |
| Merge / archive | No | No | Yes | Yes |
| Change organisation/group default | No | Only if authorised to manage that entity | Yes if authorised | Yes |

Do not leak restricted events via location endpoints. `Location` being visible does not imply visibility of every event at it. Audit changes and enforce policies server-side.

## 5. Phased implementation and AI coding prompts

Each phase is independently reviewable. Run the prompt against **both repositories** when relevant. AI must inspect code first, report mismatches and propose minimal changes; never invent existing files or APIs.

### Phase 0 — Repository and data audit (mandatory)

**Deliverables:** `docs/location/00-current-state.md`, ER diagram, schema inventory, endpoint/component inventory, migration risk assessment.

**AI prompt:**

```text
Inspect the current Rails API and React frontend of BeachVolleyballProject. Locate actual models, schema, migrations, controllers, serializers, authorization, tests, forms and routing for Address, Organisation, Group, Training and Tournament. Find all existing free-text location/address fields, existing geocoder gems and coordinate fields. Identify User -> Account identity conventions, creator/curator permissions, and existing historical records. Do not edit code. Write docs/location/00-current-state.md with file paths, relationship diagram, exact backfill mappings, conflicts, unknowns, and a migration-safe implementation recommendation. Explicitly determine whether Address is already reusable and whether Group's organisation relationship is optional.
```

**Gate:** Review findings and resolve Address reuse, auth FK target and existing field mappings before writing migrations.

### Phase 1 — Schema and core Location domain

**Deliverables:** migrations, Location and LocationAlias models, constraints, associations, model specs, factories.

**AI prompt:**

```text
Based on the approved location audit, implement a minimal reusable Location model and LocationAlias in Rails. Reuse existing Address if compatible, otherwise document why not. Add validated coordinates, timezone, normalized name, geocoding provenance/status, verification, creator, active flag, and optional merge tombstone. Use the project's actual authentication and authorization models for foreign keys. Add nullable references to Organisation.default_location_id, Group.default_location_id, Training.location_id, Tournament.location_id, and optional location_detail fields. Preserve legacy fields. Add safe indexes and FK delete restrictions. Add model specs for coordinate bounds, coordinate pair constraint, normalization, aliases, archiving and associations. Do not call external APIs.
```

**Gate:** migrations up/down tested on a copy; all old code still works; no destructive changes.

### Phase 2 — Geocoding service, job and provider configuration

**Deliverables:** Geocoder setup, service adapter, background job, retry/error handling, rate limit, manual override policy, tests.

**AI prompt:**

```text
Integrate Rails Geocoder with a configurable geocoding service, initially Nominatim only if policy permits. Create GeocodeLocationJob triggered explicitly after creation/update, not during validation and not on every save. Build structured queries from location name + locality + state + country. Use an identifiable User-Agent/contact, persistent cache where appropriate, <=1 request/second across workers, backoff on 429/5xx, bounded retries, and no public Nominatim autocomplete. Return candidate result(s) and preserve provider metadata; never silently overwrite manually corrected/verified coordinates. Make geocoding idempotent and protect against stale jobs using version or updated_at checks. Provide fake-provider tests and document provider terms and environment configuration. Do not expose API keys to React.
```

**Gate:** tests cover failure, timeout, ambiguous beach, rate limit, stale job, manual pin and verification.

### Phase 3 — Deterministic beach seed dataset

**Deliverables:** reviewed seed dataset, idempotent import, provenance, seed tests.

**AI prompt:**

```text
Create an idempotent seed/import of approximately 20-30 common Sydney beaches including Coogee, Maroubra, Manly, Bondi, Bronte, Clovelly, Tamarama, Freshwater, Dee Why and Narrabeen. Use coordinates verified against reliable mapping data and committed to the repository; never geocode during seeds, tests or CI. Record coordinate source, date checked, location name, locality, timezone Australia/Sydney and optional aliases. Match existing locations by stable seed key or carefully scoped canonical identity, avoid overwriting verified/manual pins, and make repeated seeds produce no duplicates. Flag any unverified coordinates for manual review rather than inventing values.
```

**Gate:** running seeds twice creates no duplicates; no outbound requests.

### Phase 4 — Defaults and event location semantics

**Deliverables:** default resolver, API representation, tests, preserved event history.

**AI prompt:**

```text
Implement optional default_location_id on Organisation and Group with group override and organisation fallback. When creating a Training or Tournament, suggest the resolved default but persist the actual location_id on the event. Add optional location_detail for Court 1 / North end. Never dynamically replace an existing event's location when a group/organisation default changes. Update serializers, strong parameters, validations, API docs and request specs. Ensure independent groups work and the client can override a suggested location. Respect event visibility and existing permission rules.
```

**Gate:** changing defaults leaves historical event locations unchanged.

### Phase 5 — Existing-data backfill and rollout

**Deliverables:** dry-run mapping, audit CSV/JSON, reversible/idempotent backfill, unresolved queue, staged constraints.

**AI prompt:**

```text
Inventory all existing training/tournament/organisation/group free-text locations and addresses. Write a dry-run backfill task that normalizes names, matches known Locations/aliases with locality context, and reports ambiguous/unmatched rows without mutating them. Add an explicit --apply mode with transactional batches, logging, resumability and an audit file. Do not guess ambiguous matches or invoke geocoding during migration. Keep location_id nullable and old fields readable until backfill and frontend rollout are verified. Generate a reconciliation report (total, mapped, ambiguous, missing) and rollback instructions. Tighten NOT NULL only if actual business rules and data permit.
```

**Gate:** every existing row accounted for; backups tested before production apply.

### Phase 6 — Location API, search and selector UI

**Deliverables:** scoped CRUD/search endpoints, LocationSelector, creation proposal form, integration tests.

**AI prompt:**

```text
Build Rails API endpoints to list/search active Locations by name, aliases and locality, show details, create proposals and edit own unverified proposals; curator/admin verification actions are separate. Apply pagination, authorization, parameter validation and throttling. In React/Vite, implement reusable LocationSelector with local database search, loading/empty/error states, choose existing, and Add new location. Use it in Training and Tournament forms and in Organisation/Group default location settings. Show optional location_detail only on events. Do not call public Nominatim for autocomplete. Include accessible keyboard navigation, tests and no regression to current forms.
```

**Gate:** can select a seeded beach and specify Court 1; no direct external search on keystrokes.

### Phase 7 — Duplicate detection, verification and merge

**Deliverables:** duplicate candidates, curator dashboard, verified pin flow, transactional merge, audit trail.

**AI prompt:**

```text
Add duplicate candidate detection using normalized names, aliases, scoped locality, provider+place ID and geographic proximity (initial review radius around 200 m, configurable, not automatic identity). Present candidates before a proposed location is saved; allow justified distinct places. Implement curator/admin review: confirm or manually adjust coordinates, verify, reject/archive proposals. Build a safe merge service that transactionally repoints Organisation.default_location_id, Group.default_location_id, Training.location_id, Tournament.location_id and any newly discovered references, preserves useful aliases, records before/after audit and retains an archived redirect/tombstone. Prevent merge cycles, conflicting canonical IDs and deletion of referenced locations. Test rollback and concurrent operations.
```

**Gate:** merging Coogee Bch into Coogee Beach retains all events and defaults; audit is inspectable.

### Phase 8 — Admin operations, monitoring and documentation

**Deliverables:** curator dashboard, operational tasks, `docs/location/README.md`, incident runbook, observability.

**AI prompt:**

```text
Create a location admin dashboard with pending verification, failed geocodes, suspected duplicates, archived records and merge history. Add instrumentation for geocoding request count, provider failures, queue delay, retry counts and unresolved backfill. Write docs/location/README.md with setup, env vars, database migration/rollback, seeding, dry-run/apply backfill, manual coordinate correction, re-geocode, verify, merge, archive, provider policies, troubleshooting, and how each command works. Use actual project commands from the repositories, not invented rake task names. Add sample development workflows and production deployment checklist.
```

**Gate:** a maintainer can operate and recover without relying on undocumented AI instructions.

### Phase 9 — Final QA and safe production rollout

**Deliverables:** test report, migration rehearsal, release checklist, rollback decision points.

**AI prompt:**

```text
Run Rails unit/request/job tests and frontend unit/integration/E2E tests for location creation, selection, permissions, defaults, history, backfill, duplicate detection, verification and merge. Rehearse database backup/restore and migrations against a staging copy for Neon and Supabase as applicable. Confirm Cloudflare R2 object storage is unaffected by location DB changes. Check production queue worker availability on Render, provider rate limiting across workers, seed determinism, security and API compatibility. Produce docs/location/09-release-checklist.md listing commands actually executed, pass/fail results, unresolved issues, deploy order, rollback instructions and manual acceptance tests. Do not deploy without approval.
```

## 6. API design (illustrative; adapt to existing conventions)

```text
GET    /api/v1/locations?q=coogee&active=true
GET    /api/v1/locations/:id
POST   /api/v1/locations                  # proposal
PATCH  /api/v1/locations/:id              # authorised edit
POST   /api/v1/locations/:id/geocode      # authorised retry
POST   /api/v1/locations/:id/verify       # curator/admin
POST   /api/v1/locations/:id/archive      # curator/admin
GET    /api/v1/locations/:id/duplicates   # curator/admin
POST   /api/v1/locations/:id/merge        # curator/admin
```

Return `id`, `name`, `location_type`, locality, coordinates when allowed, timezone, verification status and active status. Never expose internal notes or private audit data to ordinary users.

## 7. Edge cases and tests

- Coogee Beach vs Coogee Bch: suggest canonical match; do not create duplicate without warning.
- Two distinct courts/venues within 200 m: allow separate canonical places when justified.
- Beach pin vs street address geocode: curator can move pin without future auto-overwrite.
- Missing or ambiguous address: Location still valid; geocoding may remain pending/manual.
- External provider unavailable: event selection of existing places still works.
- Same name in different states/countries: scoped uniqueness and locality-sensitive matching.
- Archived location referenced by an old tournament: remains visible in historical record but unavailable for new selections.
- Independent group: owns default directly; group with organisation inherits only for prefill.
- Multiple tournament divisions: all can share tournament location; no changes to division model.
- Changing default after training creation: no change to persisted training location.
- Date/time zone: use IANA zone for event display and future scheduling, not fixed UTC offset.
- Security: only authorised users can edit locations, verify, merge or change defaults; API must reject bypass attempts.
- Concurrency: two users propose same location simultaneously; merge service safely locks and validates references.
- Legacy clients: tolerate missing location_id during transition; remove compatibility only after verification.

## 8. Deferred enhancements

1. External Places autocomplete via licensed provider (not public Nominatim), separate from geocoding.
2. Interactive map with draggable verified pin and provider-compliant map tiles/attribution.
3. Weather forecasts based on coordinates and event time.
4. PostGIS geography point + GiST index for high-volume distance search; check extension support on each Neon/Supabase database.
5. Structured `LocationArea` / `Court` and booking availability.
6. Multi-venue tournament join model, only when tournament requirements demand it.
7. Multiple provider references and provider-switch reconciliation.

## 9. Recommended delivery order and sign-off

**Milestone A (foundation):** Phases 0–3. Approve schema and verified seed dataset.  
**Milestone B (usable workflow):** Phases 4–6. Events and defaults use existing canonical locations.  
**Milestone C (data quality):** Phases 7–8. Curator review, merge, docs and observability.  
**Milestone D (release):** Phase 9. Staged rollout and production verification.

**Decisions to confirm after Phase 0:** actual Address schema; whether verified location coordinates can be public; which roles may propose; whether training/tournament location is mandatory; which actor model is used for `verified_by`; available Render background worker strategy; and geocoding provider terms.

**Definition of done:** Existing data preserved; seeded beach selector works; group/organisation defaults prefill but never mutate history; users can add a location through a moderated workflow; manual pins remain authoritative; duplicates can be merged safely; jobs never block ordinary requests; all permissions and tests pass; operators have reproducible commands and rollback documentation.
