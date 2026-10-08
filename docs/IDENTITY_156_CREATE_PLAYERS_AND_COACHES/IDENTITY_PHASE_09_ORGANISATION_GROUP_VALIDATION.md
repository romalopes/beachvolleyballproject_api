# Identity Phase 9: Organisation and Group compatibility

## Status

Complete. The existing Person-keyed model supports the planned organisation and group contexts; this phase adds end-to-end regression coverage. No schema or production behavior change was needed.

## Validated invariants

- Organisation and Group records do not own or create Person identities.
- A Group can be independent (`organisation_id: nil`) or tied to one Organisation.
- OrganisationMembership and GroupMembership remain keyed by Person, not Account, User, PlayerProfile, or CoachProfile.
- One Person can carry a PlayerProfile and multiple independent CoachProfiles while belonging to multiple Organisations and Groups.
- An Organisation-linked group roster must contain active members of that Organisation. An independent group has no organisation-sharing constraint.
- Group membership grants neither organisation membership nor organisation management authority. Organisation and group authorization still use their existing membership and role checks.
- Successful Person consolidation preserves non-duplicate organisation/group membership rows and their IDs, roles, and statuses. Phase 8's explicit collision resolution applies only where the database's Person/container uniqueness rule prevents both rows from being attached to the canonical Person.

## Verification

The focused run passed: 30 tests, 132 assertions, 0 failures, 0 errors. It included all Group API controller tests plus the new combined identity/consolidation scenario.

The combined scenario gives one Person a PlayerProfile and multiple CoachProfiles, memberships in separate Organisations, and both an organisation-linked and an independent Group; it consolidates that Person into another Person who already has an account, profile, and memberships. It verifies that every distinct profile and membership row remains attached to the canonical Person with its record ID and lifecycle status intact.

## Added coverage

- `test/services/identity_organisation_group_compatibility_test.rb`
- `test/controllers/api/v1/groups_controller_test.rb`: group membership does not grant standing to create a group for an Organisation.

Existing Group and Organisation model/API tests cover the remaining sharing, lifecycle, and role rules.
