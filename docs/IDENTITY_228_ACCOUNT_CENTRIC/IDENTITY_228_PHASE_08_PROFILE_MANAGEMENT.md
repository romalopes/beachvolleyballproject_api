# Issue 228 — Phase 8: Profile management dashboard

## Status

Implemented. Focused frontend and Rails suites pass. The management dashboard is available from the existing `/identity` route to Admin, Curator, and Coach users.

## Dashboard behavior

The Identity page now embeds a role-gated **Profile management** panel with separate **Claims** and **Invitations** tabs.

### Claims

- Filter by PlayerProfile/CoachProfile and claim status (pending, approved, rejected, cancelled, or all history).
- Paginated results display the target profile and decision state. Reviewer-visible verification method and rejection note are shown when present.
- Approve and Reject controls render only when the backend reports `can_review` for that claim. Approval requires a verification method; rejection accepts an optional reason.
- Existing `PlayerClaim#reviewable_by?` remains the decision authority: Admins may review any profile; Coaches may review profiles they recorded. Curators can inspect claim records in their current oversight scope, but receive no approve/reject controls and the API continues to reject their decision requests.

### Invitations and profiles

- Search a paginated profile directory, filtering by profile type, active/archived status, and whether the profile is Account-linked or unlinked.
- Directory rows link to the relevant profile detail and expose only the name, type, lifecycle status, and account-link state.
- Eligible unlinked profiles provide a recipient email field and **Create invite link** action. An email can belong to an existing Account or a new registrant; the API uses the verified exact-email rule. The generated link is held only in component state and has a copy action.
- Invitation history is independently filterable by subject type and active/accepted/declined/cancelled/expired status. An active invitation can be cancelled. A new invitation can replace an active one; the previous invitation is revoked by the existing service, and the replacement is delivered when an email is provided.
- Invitation summaries add the claimable display name but continue to exclude the token and token digest.

## API and authorization

### Management endpoints

- `GET /api/v1/player_claims?management=1` returns paginated claims and accepts `status` and `claimable_type` filters.
- `GET /api/v1/claim_invitations?management=1` returns paginated invitation history with the same filters.
- `GET /api/v1/claim_invitations/claimables` returns the paginated directory and accepts `claimable_type`, `status`, `link_state`, and `q`.
- Each endpoint requires authentication and a manager role. Filtering and record scope are applied on the server. A Coach's management directory and claim history are limited to profiles the Coach recorded. Decision permissions remain separately checked by `ProfilePolicy#review_claim?` for every approve/reject request.
- The `expired` invitation filter includes active rows whose expiry time has passed, matching the effective status returned by the invitation model.

### Curator scope adaptation

The Phase 8 prompt describes Curator access as organisation-scoped. The repository's existing authorization model assigns the Curator role globally: `ProfilePolicy` grants Curators oversight across profiles, and there is no organisation-specific Curator assignment relation. This implementation preserves that established scope for listing and invitation operations rather than introducing a new role-assignment model during this phase. Curators still cannot approve/reject claims. A future organisation-scoped Curator policy needs a persisted assignment model and its own authorization migration/tests before global oversight is narrowed.

This decision preserves current `ProfilePolicy` behavior. It is the one scope difference from the Phase 8 prompt and is intentionally recorded for review.

## Files

- New `ProfileManagementDashboard` React component and component tests.
- Identity integration now replaces the earlier one-off reviewer and invitation panels with the role-gated dashboard.
- `ProfileManagementScope` centralizes management profile selection: Admin/Curator use current oversight scope; Coach uses profiles recorded by that Account.
- `ClaimInvitationsController` and `PlayerClaimsController` provide management filters and paginated summaries.
- Claimable profile summaries contain no email, phone, date of birth, or token data.

## Verification

- Frontend Identity and management dashboard tests: **17 tests passed**.
- Frontend `npm run build`: passed. Vite reports the repository's existing large-chunk warning (>500 kB).
- Rails invitation and claims controller suites: **47 tests, 188 assertions, 0 failures/errors**.
- Ruby syntax checks and `git diff --check`: passed.

## Next phase

Phase 9, removing People workflows, is not started.
