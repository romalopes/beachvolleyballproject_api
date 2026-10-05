# Identity Phase 18: One claim workflow

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

`player_claims` gained the same polymorphic subject and a partial unique index
across all types. `player_profile_id` is retained and a check constraint
(`player_claims_single_subject`) guarantees a claim names exactly one subject, so
existing responses and clients are unaffected.

### The auto-approve gate

**An invitation links an identity immediately only when the club actually
emailed it to the address the recipient controls.** All four conditions must
hold:

1. `invitee_email` is set,
2. `emailed_at` is set (the mailer accepted the message),
3. the signed-in user's address matches, and
4. that address is verified.

Anything else — a link copied by hand, an invitation whose email never went out,
an unverified account, a backfilled row — creates a **pending claim for staff
review** instead. `redeem!` returns `outcome: "linked"` or
`outcome: "pending_review"`, and `/identity` says which happened.

This is fail-closed on purpose. `CLAIM_INVITATION_EMAIL_ENABLED` defaults to
`false`, so a deployment without SMTP never auto-approves anything, and a mail
failure downgrades to review rather than granting an identity.

Backfilled invitations have no `emailed_at` and therefore require review, which
is the safe direction.

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

## Verification

Backend `bin/rails test` — **1,429 runs, 5,789 assertions, 0 failures, 0 errors**
(one pre-existing unrelated skip). Frontend `npm test` — **878 tests across 79
files, 0 failures**. `tsc -b` clean; RuboCop clean on all touched files.

New coverage: `ClaimInvitationServiceTest` (13 tests) walks every branch of the
auto-approve gate — emailed auto-link, hand-copied link to review, no address to
review, unverified address to review, wrong address refused generically, one
pending claim per subject, reissue revokes, coach profile claimable, coach with a
Person ineligible, person subject auto-link and review, ineligible persons, and
expired/unknown tokens. `ClaimInvitationsControllerTest` (7) covers the
polymorphic endpoints including refusing an unknown subject type.

## Known limitations

- `emailed_at` means *handed to the mailer*, not *arrived in the inbox*.
  Confirming real delivery needs a bounce/complaint webhook, which this app has
  no infrastructure for. A bounce to a recycled address could still auto-approve.
- The model and table are still called `PlayerClaim`/`player_claims`. Renaming
  is a follow-up; the subject is polymorphic and `player_profile_id` is
  retained deliberately for compatibility.
- The legacy tables and endpoints remain and are **not yet dropped**.