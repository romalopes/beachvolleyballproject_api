# Identity Phase 17: Claiming a known Person

## Goal

Let a club record a real Person, add their email, and invite them to connect their own login Account to that existing identity. This is distinct from inviting someone to claim an unlinked placeholder PlayerProfile.

## User flows

### Known Person, email on file

1. A coach or administrator records the Person and any player or coach profiles.
2. From **People**, staff selects **Invite to account**. The invitation is restricted to the Person's recorded email. The application can email the link when invitation delivery is enabled; otherwise staff copies and shares the one-time link.
3. The recipient signs in or creates an account, verifies that email, and accepts the invitation on **Identity**.
4. The Account connects to the existing Person, retaining every profile and history record. The invitation is single-use and expires after seven days.

New signups currently receive an empty signup Person for compatibility. On acceptance, the service moves that Account to the invited Person and marks the empty signup Person as merged into it. It permits this only for the same user's signup-created record with no profiles or memberships. Other Account conflicts are rejected.

### Placeholder player profile

When the club has only a player profile and no Person details, staff uses the separate player-profile claim invitation. That flow creates a Person for the claimant and submits a claim request for approval. It does not attach the claimant to a known Person.

## Rules and safeguards

- Invitation issue requires an active, accountless Person with a valid email.
- The Person's email must still match the invitation, and the signed-in User must have verified the same address.
- A user with a non-placeholder Person or any existing identity history cannot move that Account through this flow.
- Raw tokens are returned only at creation; only a digest is stored. Tokens are one-use and revocable.
- Linking keeps player and coach profiles on the recorded Person; it does not create or reassign profiles.
- A Person without an email must be updated from **People** before staff can invite them.

## Implementation

- Added `PersonAccountInvitation`, service, optional mail delivery, API endpoints, and migration.
- Added People controls for creating/revoking invitations and copying a one-time link.
- Added invitation acceptance to `/identity`.
- Added focused backend and frontend coverage.

## Verification

Backend `bin/rails test` — **1,407 runs, 5,704 assertions, 0 failures, 0 errors**
(one pre-existing unrelated skip). Frontend `npm test` — 874 tests across 79
files, 0 failures. `tsc -b` clean; RuboCop clean on the touched files.

### Defect found and fixed while completing this phase

`PersonAccountInvitationService.redeem!` re-pointed the Account with
`account.update!(person: person)` and *then* retired the signup placeholder with
`placeholder.update!(status: "merged", ...)`. That order silently undid the
re-point: `placeholder` had been loaded through `account.person`, so once the
Account moved, the placeholder object was stale and its cached `has_one :account`
inverse wrote the old `person_id` back.

The Account update genuinely succeeded and was then reverted, which is why the
symptom was a 200 response with the Account still on the placeholder rather than
an exception. Retiring the placeholder **first** never touches the Account's
inverse, so the move survives. Both the service test and the controller test
assert the resulting `account.person_id`, and both failed before the fix.

### Test setup correction

`User` has no `after_create` callback for `Account`, so `User.create!` alone
leaves the user with no Account and therefore no signup Person. The tests now
build the Account explicitly to reproduce the state a user is genuinely in by the
time they redeem (see `Api::V1::AccountsController`, which builds it lazily).
