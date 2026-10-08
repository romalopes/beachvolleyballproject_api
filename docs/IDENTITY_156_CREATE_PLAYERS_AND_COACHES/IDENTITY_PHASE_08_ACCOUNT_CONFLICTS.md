# Identity Phase 8: Account and profile conflicts

## Status

Implemented and verified with focused service and API tests. This phase formalizes the conflict policy already introduced for safe Phase 7 consolidation.

## Policy

### Accounts

- If only the source has an Account, consolidation reassigns that Account's `person_id` to the canonical Person. The Account and User rows are never replaced or deleted.
- If only the canonical Person has an Account, it stays attached there; a source account does not exist to transfer.
- If both people have Accounts, consolidation always blocks with `account_conflict`, in either source/target direction. No endpoint picks a login identity, merges Users, disables a login, or detaches an Account. That needs a separate authentication/account remediation policy before retrying consolidation.

### Profiles

- Multiple PlayerProfiles and CoachProfiles per Person are supported since Phase 2/6. Matching profile kinds are not conflicts.
- Every profile remains a separate row with its ID and provenance. Consolidation only repoints `person_id`; linked assessments, coaching periods, training participants, and claims keep their existing profile IDs.

### Duplicate memberships

- OrganisationMembership and GroupMembership collisions are detected for all statuses. Database uniqueness is on the Person/container pair, so even ended/pending/suspended duplicates cannot coexist on the canonical Person.
- Ordinary `POST /api/v1/person_consolidations` continues to return HTTP 409 and makes no writes when membership collisions exist.
- An administrator may instead call `POST /api/v1/person_consolidations/resolve` with the same `person_consolidation` source/target selection and one `membership_resolutions` item per membership conflict:

```json
{
  "person_consolidation": {
    "source_person_id": 123,
    "canonical_person_id": 456
  },
  "membership_resolutions": [
    {
      "type": "organisation_membership_conflict",
      "container_id": 12,
      "keep_record_id": 321,
      "reason": "Verified against the club register"
    }
  ]
}
```

- The selected row is retained (and moved to the canonical Person if it belonged to the source). The competing membership row is removed to satisfy the unique Person/container key. Its complete pre-removal attributes, original ID, the selected ID, and the administrator's reason (required, at most 500 characters) are written into the successful PersonConsolidation audit in the same transaction.
- Every current membership conflict must have exactly one valid resolution. Missing, duplicate, stale, or extra decisions do not partially change data. Two-Account conflicts remain blocking even when membership decisions are supplied.
- Both the ordinary and resolution endpoints are administrator-only. The audit actor is the real authenticated administrator, including during impersonation.

## Verification

Focused service and controller tests pass: 15 tests, 86 assertions. They cover both two-Account conflict directions, both one-Account cases, retained multiple player/coach profiles, duplicate organisation/group memberships, explicit membership selection and full discarded-row snapshots, authorization, and no partial writes on unresolved conflicts.

No schema migration was needed: resolution snapshots use the existing JSONB `PersonConsolidation.result`. The Phase 7 migration has already created that audit store.

## Files

- `app/services/person_consolidation_service.rb`
- `app/controllers/api/v1/person_consolidations_controller.rb`
- `config/routes.rb`
- `test/services/person_consolidation_service_test.rb`
- `test/controllers/api/v1/person_consolidations_controller_test.rb`
