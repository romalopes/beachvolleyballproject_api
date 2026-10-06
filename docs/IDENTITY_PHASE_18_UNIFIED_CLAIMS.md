# Identity Phase 18: One claim workflow

> **Historical verification note (2026-10-05):** The test/build results in this
> document record the original Phase 18 implementation only. Issue 225 later
> changed invitation authorization and compatibility controllers; those later
> changes have not been tested or built in this workspace.

## What was wrong

Two invitation systems had grown for the same job:

| | `player_claim_invitations` | `person_account_invitations` |
|---|---|---|
| Subject | an unlinked `PlayerProfile` | a `Person` with no `Account` |
| Issuer recorded as | `created_by_person_id` (a Person) | `invited_by_id` (a User) |
| Claimant identified by | a Person | a verified-email User |
| `invitee_email` | optional | required |
| Completes | pending claim → staff approve | immediately on redeem |

Same token digest, same seven-day expiry, same revoke-on-reissue, same
one-active-per-subject index — written twice, disagreeing about the rules. A
coach could not claim a coach profile at all, because Phase 2 had made
`coach_profiles.person_id` `NOT NULL` on the stated grounds that "coach profiles
have no unassigned-coach workflow".

## What changed

### One polymorphic subject

`claim_invitations.claimable_type` / `claimable_id` carries the subject:

- `PlayerProfile` — the profile adopts a Person
- `CoachProfile` — the profile adopts a Person
- `Person` — a login Account adopts this identity

`ClaimSubject` holds eligibility and the effect of approval per kind, so the
service, controller and UI carry one code path instead of three. Existing rows
from both legacy tables are backfilled; **the legacy tables and their endpoints
are kept for one release** so an existing client keeps working.

Player and coach profile invitations cover both recorded states: a profile
without a Person adopts the claimant's Person after approval, while a profile
already linked to an accountless Person connects the claimant's Account to that
existing Person. When that Person has an email address, the invitation is
restricted to that address and a verified match can connect immediately.

`player_claims` gained the same polymorphic subject and a partial unique index
across all types. `player_profile_id` is retained and a check constraint
(`player_claims_single_subject`) guarantees a claim names exactly one subject, so
existing responses and clients are unaffected.

### The auto-approve gate

**An invitation links an identity immediately when the signed-in recipient
proves control of the invitation's exact email address.** These conditions must
hold:

1. `invitee_email` is set,
2. the signed-in user's address matches, and
3. that address is verified.

Whether the link was emailed or copied by hand does not affect this proof. An
unverified matching address is asked to verify and may retry; the invitation
remains active. Redeeming an active profile invitation accepts it and links the
signed-in account immediately. `redeem!` returns `outcome: "linked"`; manual
profile claims remain the separate staff-review path.

The verified matching email is the authorization check. `emailed_at` remains
delivery telemetry, but delivery failure does not turn a verified, matching
recipient into a staff-review request.

Backfilled invitations follow the same rule: an email-restricted invitation can
link after verification; an invitation without an address requires review.

### Coach parity

Migration `20261006000004` reverses Phase 2's `require_person_for_coach_profiles`:
`coach_profiles.person_id` is nullable and a `display_name` column is added,
required exactly when there is no Person. `CoachProfile#full_name` and
`#account_status` became nil-safe, `CoachesController` serializes `display_name`
and now keeps a `person: null` key, and the record/edit screens offer the
accountless mode for coaches.

## Defects found and fixed while building this

1. **A silent revert of the account re-point** (in the uncommitted Phase 17
   work). `redeem!` moved the Account and then saved the stale placeholder
   object, whose cached `has_one :account` inverse wrote the old `person_id`
   back. The endpoint returned 200 with the Account still on the wrong Person.
   Fixed by retiring the placeholder first; see
   `IDENTITY_PHASE_17_PERSON_ACCOUNT_CLAIMS.md`.
2. **The expiry branch rolled back its own write.** Marking an invitation
   expired and then raising inside the transaction discarded the status change.
   The refusal is now raised *after* the transaction commits.
3. **`invitation_owner?` resolved against `nil`** on the member `show`/`revoke`
   actions, which carry no `claimable_type` param. Ownership now comes from the
   invitation's own subject.
4. **The `player_claims` migration failed on a database holding real claims.**
   The backfill wrote the polymorphic pair but left `player_profile_id` set, so
   every row had *two* subjects and violated `player_claims_single_subject`. The
   test database has no pre-existing `player_claims` rows, so the backfill was a
   no-op there and the suite passed against a database shape that no deployment
   has. Fixed by clearing the legacy column as part of the backfill — after
   relaxing it to nullable, which itself has to happen first.

   Clearing that column then broke two query paths that had joined on it, both of
   which would have failed silently on real data:
   - `player_claims_controller#index` used `where(player_profiles: …)`, an inner
     join on the now-NULL column, which would have **removed every migrated
     pending claim from a coach's review queue**.
   - `PlayerClaimService.approve!` used `claim.player_profile`, which would have
     raised `NoMethodError` on `nil` when approving a migrated claim.

   Both now go through `PlayerClaim#subject`, with `pending_for_owner` and
   `reviewable_by?` centralising the rule. `summary` derives `player_profile_id`
   from `claimable_id` so the API key is unchanged for clients.

   `PlayerClaimTest` now covers a polymorphically-stored claim end to end — the
   shape a backfill produces, which a fresh fixture row alone would not catch.

## Verification at original Phase 18 completion

Backend `bin/rails test` — **1,429 runs, 5,789 assertions, 0 failures, 0 errors**
(one pre-existing unrelated skip). Frontend `npm test` — **878 tests across 79
files, 0 failures**. `tsc -b` clean; RuboCop clean on all touched files.

Historical coverage at original Phase 18 completion: `ClaimInvitationServiceTest`
(13 tests) encoded the earlier delivery-based gate, including emailed auto-link
and hand-copied link review. That expected behavior was superseded by Issue 225's
verified-email decision and these tests need to be revised. The suite has not
been run against the current Issue 225 changes. `ClaimInvitationsControllerTest`
(7) was the original polymorphic endpoint coverage, not current verification.

## Known limitations

- `emailed_at` means *handed to the mailer*, not *arrived in the inbox*. It is
  diagnostic telemetry only; account linking depends on exact verified-email
  equality. A recycled email address remains a general email-ownership risk.
- The model and table are still called `PlayerClaim`/`player_claims`. Renaming
  is a follow-up; the subject is polymorphic and `player_profile_id` is
  retained deliberately for compatibility.
- The legacy tables and endpoints remain and are **not yet dropped**.
