# Identity Phase 10: Assessment compatibility

## Status

Complete. Assessment rows already referenced PlayerProfile and CoachProfile IDs, so no assessment schema change was needed. This phase adds regression coverage for claims, multiple profiles, Person consolidation, and existing visibility rules.

## Verified behavior

- Assessment history belongs to PlayerProfile, not Account or Person.
- Approving a PlayerClaim links the existing PlayerProfile to the claimant Person. The claim does not replace the profile or edit its assessments.
- A PlayerProfile's private/shared visibility is unchanged by claim approval.
- Multiple PlayerProfiles belonging to one Person retain separate assessments and histories.
- Person consolidation repoints profiles while leaving assessment IDs, player_profile_id, coach_profile_id, scores, reported values, scales, statuses, timestamps, and notes unchanged.
- Assessment attribution remains attached to the original CoachProfile ID after the associated Person is consolidated.
- Existing assessment rules continue to control private player visibility and stakeholder access to draft/withdrawn rows. The identity change does not widen assessment access.

## Verification

The focused run passed: 143 tests, 530 assertions, 0 failures, 0 errors. It covered the new identity/assessment integration test plus PlayerClaim controller tests, Assessment model/API tests, and Player API tests.

## Added or extended coverage

- `test/services/identity_assessment_compatibility_test.rb`: distinct assessment histories on multiple profiles survive Person consolidation, with coach attribution and assessment fields unchanged.
- `test/controllers/api/v1/player_claims_controller_test.rb`: assessment-before-claim then approval preserves assessment fields and private profile visibility.

## Schema and rollout

No migration or production data change was required. Existing foreign keys and profile-based assessment associations already satisfy the Phase 10 contract.
