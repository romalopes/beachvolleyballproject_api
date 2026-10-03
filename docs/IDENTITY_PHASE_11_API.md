# Identity Phase 11: Identity API completeness

## Status

Planned. Phases 2–6 have delivered additive identity, claim, candidate, invitation, and multi-profile behavior; remaining endpoints depend on conflict policy and UI needs.

## Goal

Provide a coherent server-authorized API for current Person context, profile collections, claim lifecycle, invitations, and administrative consolidation.

## Scope

- Current Person with Account, all PlayerProfiles/CoachProfiles, and relevant memberships.
- Player profile CRUD and claim/candidate status contracts.
- Claim approve/reject/cancel and invitation create/redeem/revoke/status contracts.
- CoachProfile create/read/update/archive with multiple records per Person.
- Consolidation preview, conflict report, execution, and audit retrieval.

## Acceptance checks

- API follows existing routing and response conventions.
- Sensitive fields are limited to authorized callers.
- All submitted Person/Profile/Account/organisation identifiers are authorized server-side.
- Request, controller, and service tests cover positive and hostile cases.

## Dependencies

Complete domain decisions from Phases 7–10 before finalizing consolidation payloads. This file will be updated to distinguish existing endpoint coverage from new work at implementation time.
