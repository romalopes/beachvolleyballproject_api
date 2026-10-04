# Identity Phase 11: Identity API completeness

## Status

Implemented. Existing identity routes were audited and the API gaps below were filled. No database migration was needed.

## Goal

Provide a coherent server-authorized API for current Person context, profile collections, claim lifecycle, invitations, and administrative consolidation.

## API contract

| Area | Routes and behavior | Access |
| --- | --- | --- |
| Current account context | `GET /api/v1/me` returns the account and Person identifiers, all player and coach profile summaries, plus the caller's organisation and group memberships. The singular `player_profile_id` remains for older clients. | Authenticated account only; no other person's private membership context is included. |
| People and profiles | People support index/search, show, create, update, destroy, and admin promotion. Players and coaches support index, show, create, and update. Profile status changes provide archive/restore while preserving historical records. A Person may expose multiple player and coach profiles. | Existing staff/admin and profile visibility rules apply. Nested organisation membership writes are checked against the target Person and each organisation. |
| Player claims | `GET /player_claims`, `GET /player_claims/:id`, `GET /player_claims/candidates`, and `POST /player_claims`; claim members support `approve`, `reject`, and `cancel`. Claimant identity is resolved from the authenticated account; submitted Person identifiers do not select the claimant. | Claim and candidate data are scoped to the authenticated user and authorized profile owner/reviewer. |
| Claim invitations | Invitations support index, show, create, redeem, and revoke. Show/index return safe status metadata, never the raw token or token digest; the raw token is only returned on creation. | Owners and authorized administrators; unrelated users receive a concealed not-found response for show/revoke. |
| Person consolidation | `POST /person_consolidations/preview`, `POST /person_consolidations`, `POST /person_consolidations/resolve`, and `GET /person_consolidations/:id` cover preview, execution, explicit membership conflict resolution, and audit retrieval. | Administrative access. Account conflicts remain blocking; membership conflict choices are explicit and audited. |

### Nested organisation membership authorization

People, player, and coach create/update requests may carry nested `organisation_memberships_attributes`. Each submitted row is checked server-side:

- Site administrators may manage memberships.
- Other callers must be an active owner/administrator of both the existing and destination organisation.
- A membership ID must belong to the Person being changed.
- Only pending invitations may be destroyed through nested attributes; active/history rows must use the organisation membership lifecycle routes.

This prevents callers with general profile-edit access from granting themselves organisation authority or changing another Person's memberships by guessing IDs.

### Archive and restore

Player and coach profile endpoints intentionally have no hard-delete route. Clients archive or restore through the profile's `status` field on `PATCH`; the profile row and its assessment history stay intact.

## Frontend API client

`src/api.ts` now types the expanded `/me` response and exposes client methods for consolidation preview/execution/resolution/audit retrieval and invitation status retrieval. Existing profile and claim methods were retained. Request-shape tests cover consolidation routes and invitation status lookup.

## Verification

- Backend focused controller suite: **134 tests, 468 assertions, 0 failures, 0 errors, 0 skips**.
- Frontend API client tests: **37 tests passed**.
- Frontend production build: passed.
- Ruby syntax checks and `git diff --check`: passed.
- No schema changes or migration required.

The frontend build reports the existing large JavaScript chunk advisory; compilation and bundling succeed.

## Files changed

- `app/controllers/api/v1/me_controller.rb`
- `app/controllers/concerns/nested_organisation_membership_authorization.rb`
- `app/controllers/api/v1/people_controller.rb`
- `app/controllers/api/v1/players_controller.rb`
- `app/controllers/api/v1/coaches_controller.rb`
- `app/controllers/api/v1/player_claim_invitations_controller.rb`
- `config/routes.rb`
- Controller tests for `/me`, nested organisation membership authorization, and invitation status
- Frontend `src/api.ts` and `src/api.test.ts`

## Follow-up

Interactive identity workflows and context selection remain in Phase 12. Phase 13 will perform the broader security audit, and Phase 15 will run the full business integration matrix.
