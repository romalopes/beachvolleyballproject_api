# Identity Phase 12: Frontend identity experience

## Status

Implemented. The new Identity page presents the signed-in account context and the claim/consolidation flows supported by Phase 11 APIs. Player owners can issue claim invitations from an unlinked player profile. No schema changes were required.

## Delivered experience

### Identity context

`/identity` shows Account and Person IDs separately, then lists every linked PlayerProfile, CoachProfile, organisation membership, and group membership. Empty states are explicit. This is a self-service page; staff-only directory details remain in the existing People/Players/Coaches pages.

### Player claiming

- Candidate profiles are described as suggestions, with match type visible. They are never labelled as a confirmed identity.
- Users can select multiple suggestions and submit claim requests. Partial success is reported without discarding successful requests.
- The user's own claim statuses are listed, and pending requests may be cancelled.
- Coaches/admins see pending claims in their review scope and can approve or reject with a required reason. A reviewer cannot review their own claims from this screen.
- A signed-in user can redeem a one-time invitation token. A `claim_token` query is carried through login, then removed from the URL after redemption.
- An owner/admin viewing an unlinked player profile can issue a claim invitation. The raw token is shown only in the response screen and can be copied as an `/identity?claim_token=…` link. The server remains the authority for ownership and token validity.

### Coach profiles and attribution

The Identity page lists all CoachProfiles separately. Assessment-session creation already has a coach-of-record picker; the options now include the profile ID so two CoachProfiles for the same person remain distinguishable at attribution time.

### Consolidation

Admins can search people, choose source and canonical records, preview the operation, inspect conflicts, choose a membership record to keep, supply a reason, confirm consolidation, and load an audit by ID. Account conflicts are shown as blocking. The API remains authoritative for all permissions and validation.

## API adjustment needed by the UI

The claims index previously returned only a coach's review queue or an ordinary user's own claims. The controller now combines the caller's own claims with only the review rows that caller is authorized to review, removing duplicates. This lets a coach see their own claim status without widening another user's review access. A controller regression test covers this.

## Verification

- Identity page tests: **5 passed**, covering context/empty states, suggestion and multi-select semantics, invitation redemption, authentication handoff, API errors, and blocking account conflicts.
- Player claims controller tests: **20 tests, 62 assertions, 0 failures, 0 errors, 0 skips**.
- Frontend production build passed after the new page and routes were added.
- Ruby syntax and `git diff --check` passed.

## Files changed

- `src/pages/Identity.tsx` and `src/pages/Identity.test.tsx`
- `src/pages/PlayerDetail.tsx` for owner-authorized invitation creation
- `src/pages/AssessmentSessions.tsx` to label each coach profile distinctly
- `src/App.tsx` and `src/components/Sidebar.tsx` for Identity navigation
- `app/controllers/api/v1/player_claims_controller.rb` and its controller test

## Follow-up

Phase 13 performs a broader security audit. Phase 15 covers the complete business integration matrix. The frontend build still emits the existing advisory about a JavaScript chunk larger than 500 kB.
