# Issue 228 — Phase 5: Claim approval and Account linking

## Status

Implemented. Claim review uses the authenticated reviewer's Account, applies the existing profile review policy, and links the claimant Account to the existing player or coach profile in one transaction. Phase 6 invitations are documented separately.

## Behavior before this phase

- Phase 4 stored the claimant Account on new claims and allowed eligible Accounts to submit competing requests.
- Review authorization and approval still used Person-based reviewer identity, and approval did not consistently write the claimant Account onto the profile.
- Review decisions did not require a recorded identity verification method.

## Changes

- Added `player_claims.verification_method` and a database constraint for `staff_confirmed`, `government_id`, `in_person`, and `other`. It remains nullable for historical decisions; every new approval is checked by the API and service.
- Approval requires a reviewer Account and `verification_method`. The reviewer must have the existing scoped review permission and cannot approve their own claim.
- The service locks the target profile and all claims for that subject in a stable ID order, then rechecks pending status, claimant Account/Person consistency, eligibility, discovery scope, and whether the profile remains unlinked.
- The approval transaction connects the claimant Account to the existing profile. For a profile with no Person, it also attaches the claimant's Person. For an accountless existing Person, the existing safe signup-placeholder handling is used. No PlayerProfile or CoachProfile is merged or replaced.
- The claim records approved status, reviewer Account and Person, review time, and verification method.
- Other pending claims for that profile are rejected in the same transaction with reviewer, timestamp, and an internal reason. Their decision emails are queued after commit.
- A stale or already-linked target returns a conflict and leaves ownership unchanged. Forbidden, conflict, validation, and missing-record responses include stable `code` values.
- Rejection accepts an optional internal reason and records reviewer Account/Person and time. Public decision messages do not disclose the internal reason.
- Added decision email templates. Notification enqueue failures are logged without undoing a committed review decision.
- The Identity review UI requires the reviewer to select a verification method before approving. Rejection remains available without a reason.
- Preserved legacy approved rows whose historical verification method is null; new approval transitions always supply a method.

## API contract

```http
POST /api/v1/player_claims/:id/approve
Content-Type: application/json

{ "verification_method": "staff_confirmed" }
```

The API derives the reviewer Account from the authenticated session. The claimant Account comes from the stored claim; neither is accepted from the request body.

```http
POST /api/v1/player_claims/:id/reject
Content-Type: application/json

{ "rejection_reason": "Optional internal review note" }
```

Example conflict response:

```json
{ "error": "The profile is no longer eligible for this claim", "code": "conflict" }
```

## Transaction and concurrency guarantees

- Profile row locking serializes approvals targeting the same profile.
- Claims for that target are locked in ascending ID order before their status is rechecked.
- Only one competing claim can be approved. The winning Account is linked, and other pending claims receive explicit rejected audit outcomes in the same transaction.
- Any exception during profile linking or claim decision rolls back both changes.
- Decision notifications are queued only after the database transaction commits.

## Migration and files

- Migration: `20261006100009_add_verification_method_to_player_claims.rb`.
- Schema snapshot: `db/schema.rb` now includes the verification field and allowed-values constraint.
- Main implementation: `PlayerClaimService`, `ClaimSubject`, `PlayerClaimsController`, `PlayerClaim`, `ProfileClaimsMailer`, and the Identity page/API adapter.

## Verification

- `bin/rails db:migrate`: Phase 5 migration applied to the configured development database.
- Claim controller, model, and identity integration tests: **33 tests, 155 assertions, 0 failures/errors**.
- Claim invitation and profile policy compatibility tests: **23 tests, 95 assertions, 0 failures/errors**.
- New concurrency and rollback tests: **2 tests, 9 assertions, 0 failures/errors**.
- Combined related Rails suites: **58 tests, 259 assertions, 0 failures/errors**.
- Identity page: **9 tests passed**.
- `npm run build`: TypeScript and Vite build passed. Vite emitted the existing warning that the main JavaScript chunk exceeds 500 kB.

## Risks and follow-up

- The legacy `PlayerClaim`/`player_claims` naming remains for compatibility even though the subject can be either profile type.
- Delivery is asynchronous; transient enqueue failures are logged and do not roll back the approval. Operational mail delivery monitoring remains important.
- Phase 6 invitation acceptance builds on this account-based claim and linking behavior.
