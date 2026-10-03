# Identity Phase 12: Frontend identity experience

## Status

Planned. The SPA currently has API clients and basic unlinked-player rendering; interactive identity workflows and multi-profile context presentation remain.

## Goal

Make Person, Account, PlayerProfile, and CoachProfile visibly distinct in the React application.

## Scope

- Coach-created unlinked player state and authorized invitation generation.
- Candidate review, multi-selection, claim submission, and claim status.
- Safe invitation redemption after authentication.
- Person view separating Account, PlayerProfiles, CoachProfiles, and memberships.
- Multiple CoachProfile display and explicit selection when a feature requires one profile attribution.
- Admin consolidation preview, conflict display, confirmation, and result.

## Acceptance checks

- Candidate matches are presented as suggestions, never confirmation.
- Account/profile context is not collapsed into a single identity card.
- UI permission checks improve presentation only; the API remains authoritative.
- Tests cover loading, empty, conflict, error, and authorization states.

## Dependencies

Phases 6, 8, and 11 establish profile selection, conflict payloads, and API contracts.
