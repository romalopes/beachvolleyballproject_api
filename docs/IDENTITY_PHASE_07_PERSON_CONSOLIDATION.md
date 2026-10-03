# Identity Phase 7: Person consolidation

## Status

Complete for the administrator-only preview and transactional consolidation API. Phase 8 can extend these conflict rules with explicit resolution workflows; Phase 7 already blocks unsafe account and duplicate-membership merges.

## API

- `POST /api/v1/person_consolidations/preview` with `person_consolidation[source_person_id]` and `person_consolidation[canonical_person_id]` returns readiness, conflicts, and record counts without changing data.
- `POST /api/v1/person_consolidations` executes a ready consolidation and returns its audit record. An unresolved account or membership conflict returns HTTP 409 with the preview.
- `GET /api/v1/person_consolidations/:id` returns the persistent audit record.
- All actions require an authenticated administrator. The actor is the real administrator (`Current.real_user`), including during impersonation.

## Data and behavior

- `PersonConsolidation` stores source, canonical person, real administrator, completion time, and reassignment counts. A unique source-person index prevents a second consolidation audit for the same source; a database check prevents self-consolidation.
- `people.merged_into_id`, `merged_at`, and `merged_by_id` preserve a queryable source record and provenance.
- Profile records, account (when only the source has one), organisation/group memberships, and aliases are reassigned by foreign key. Their record IDs and dependent assessment/training history remain unchanged.
- Existing people merged into the source are pointed directly at the canonical person, keeping merge references shallow.
- Both people are locked in stable ID order; state and conflicts are rechecked inside the transaction. Audit creation and all reassignment roll back together.
- Historical actor/provenance IDs on claims, invitations, and organisations are retained. Consolidation does not rewrite who originally initiated, reviewed, created, or used those records.
- Two accounts or duplicate organisation/group memberships block consolidation and are returned as typed conflicts. No automatic profile deduplication, account choice, membership deletion, or fuzzy-match merge occurs.
- Source and canonical must be distinct; source cannot already be merged/consolidated; canonical cannot be merged.

## Files

- Migration: `db/migrate/20261004000001_create_person_consolidations.rb`
- Service: `app/services/person_consolidation_service.rb`
- Model: `app/models/person_consolidation.rb`
- API controller: `app/controllers/api/v1/person_consolidations_controller.rb`
- Routes: `config/routes.rb`

## Verification and limitations

The migration is recorded in `db/schema.rb` and has been applied to the configured development database. Focused service and controller tests pass: 10 tests, 58 assertions. Coverage includes read-only preview, profile/account/membership/alias reassignment, retained source and audit provenance, merge-chain flattening, account/organisation/group conflicts, rollback on audit failure, administrator authorization, audit retrieval, and replay rejection.

Production rollout remains subject to the migration and deployment planning in Phase 14. This endpoint never guesses which account or membership should win.
