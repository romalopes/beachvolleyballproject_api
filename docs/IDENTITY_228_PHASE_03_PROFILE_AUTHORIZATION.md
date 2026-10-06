# Issue 228 — Phase 3: Profile ownership and authorization

## Status

Implemented. Authentication continues through User/session. Account is the application ownership principal for PlayerProfile and CoachProfile. Roles remain on User and are exposed through Account for policy checks, consistent with the approved Phase 2 decision.

## Phase 2 state reviewed

- Phase 2 added nullable `account_id` to each profile type and backfilled only from the profile's existing Person-to-Account link.
- `created_by_account_id` is a separate creator attribution; a linked Account is not treated as the creator.
- Profiles without a mapped Account remain unclaimed.
- Person-backed profile and membership workflows remain in place. Claims/invitations still store Person actors; migrating their identity fields belongs to later phases.
- Account owns collections of profiles and ContactDetail; this phase adds the authorization rules around those links.

## Changes

- Added `ProfilePolicy` with reusable checks for `create?`, `view?`, `update?`, `invite?`, `review_claim?`, `unlink?`, `merge?`, `archive?`, and `destroy?`, plus a collection scope.
- Added Account role predicates that delegate to the existing User role assignments. Login, sessions, and role storage remain unchanged.
- Uses the Account collections and profile-link validation established in Phase 2; this phase adds authorization around those existing links.
- Updated `ProfileOwnership` to recognize linked Account ownership separately from creator Account attribution, while retaining User-ID fallback for old creator rows.
- Player and coach collections now scope regular Accounts to profiles linked through `account_id`. Training managers retain the existing shared/private and coaching-relationship catalogue rules.
- A regular Account can view its linked profiles even without a Coach, Curator or Admin role. It cannot use that link to view unrelated profiles or administer the catalogue.
- Player/coach record reads and writes now check policy at the record level. Coaches retain existing access to shared profiles; private profiles remain hidden outside their established owner/organization visibility rules.
- Claim-review and invitation authorization now use the shared policy. Coaches may review/invite only profiles they created; Admin remains the site-level override. The underlying claim and invitation data model is unchanged.
- Profile merge and delete services use the shared policy. Admin/Curator merge and Admin-only hard-delete behavior remains intact. Archive transitions use the profile update policy.
- `account_id` and `created_by_account_id` remain outside client-permitted attributes. Controller tests prove spoofed values are ignored for both profile types.

## Permission matrix implemented

| Action | Linked Account | Coach | Curator | Admin |
| --- | --- | --- | --- | --- |
| View a profile linked to the Account | Yes | If linked or visible by existing catalogue rules | Yes | Yes |
| View shared profile catalogue | Own linked profiles only | Yes | Yes | Yes |
| Create profiles | No | Yes | No | Yes |
| Update a profile | Only when also permitted by a role | Visible profiles under existing coach rules | No | Yes |
| Invite a profile | No | Only profiles created by this Account | No | Yes |
| Review a claim | No | Only profiles created by this Account | No | Yes |
| Merge profiles | No | No | Yes | Yes |
| Archive/restore | Through update permission | Through update permission | No | Yes |
| Hard-delete a profile | No | No | No | Yes, subject to dependency checks |

“Coach may update visible profiles” preserves the existing shared-content behavior. “Coach may invite/review only profiles they created” follows the distinction between creator and linked owner. A profile's creator is never changed by linking it to an Account.

## Scope and security boundaries

- Controllers still require an authenticated User; policy resolution reads that User's Account.
- Record reads conceal an inaccessible private profile with a not-found response. Non-manager writes that lack permission return forbidden; unrelated coaches cannot use a private profile ID to read it.
- Collection queries are restricted before pagination. The `include_private` catalogue option remains available to training managers as before; it does not broaden a regular Account's collection beyond its Account-scoped relation.
- The `mine` filter uses ownership/creator scope and does not accept a client-supplied owner ID.
- Account-level role methods mirror User roles; they do not independently grant privileges or create a second role store.
- Existing Curator role remains a global oversight role in this repository. No per-organization Curator permission/assignment model exists, so this phase preserves the existing global visibility/merge behavior instead of inventing scope data. This remains a limitation against the roadmap's proposed organization-scoped Curator policy.
- Claimant and reviewer records are still Person-based. This phase centralizes their authorization only; the Account-based claim schema is subsequent work.

## Verification

- `bin/rails test test/services/profile_policy_test.rb test/models/player_profile_test.rb test/models/coach_profile_test.rb test/controllers/api/v1/players_controller_test.rb test/controllers/api/v1/coaches_controller_test.rb`: **108 tests, 378 assertions, 0 failures/errors**.
- `bin/rails test test/controllers/api/v1/player_claims_controller_test.rb test/controllers/api/v1/claim_invitations_controller_test.rb test/controllers/api/v1/player_claim_invitations_controller_test.rb test/services/claim_invitation_service_test.rb test/services/player_claim_invitation_service_test.rb`: **62 tests, 242 assertions, 0 failures/errors**.
- `bin/rails test test/controllers/api/v1/coaches_controller_test.rb` after adding coach ownership mass-assignment coverage: **30 tests, 111 assertions, 0 failures/errors**.
- `ruby -c` passed for the new policy, ownership service and both profile controllers.

No migration was needed for this phase. No claim or invitation schema changes were made.
