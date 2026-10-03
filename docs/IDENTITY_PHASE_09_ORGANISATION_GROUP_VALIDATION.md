# Identity Phase 9: Organisation and Group compatibility

## Status

Planned. Existing organisation and group architecture is Person-keyed and already permits multiple memberships.

## Goal

Prove that the identity model allows one Person to belong to multiple organisations and groups, be a player in one context and coach in another, and retain independent CoachProfiles without duplicating Person membership data.

## Invariants

- Organisation and Group do not own Person records.
- Group may be independent or associated with an organisation as the existing model specifies.
- OrganisationMembership and GroupMembership remain Person-keyed.
- Membership is not a substitute for attendance, a CoachProfile, or an authorization bypass.

## Acceptance checks

- Integration coverage exercises organisation-owned and independent groups, multiple memberships, combined player/coach identity, and several CoachProfiles.
- Person consolidation does not erase or silently duplicate membership history.
- Authorization remains based on existing membership and role rules.

## Dependencies

Phases 6–8 establish profile multiplicity and consolidation behavior. This phase validates existing organization/group contracts without adding redundant membership tables.
