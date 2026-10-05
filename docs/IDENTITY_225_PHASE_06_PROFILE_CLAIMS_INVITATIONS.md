# Issue 225 — Phase 6: Profile claims and invitations

**Status:** Implemented and verified by the full backend suite. Existing tests now assert verified exact-email linking and unified invitation records. Depends on Phases 0–3.

## Objective

Make profile claims and invitations use consistent rules for PlayerProfile and CoachProfile, while retaining the distinct operation that connects an Account to a known Person.

## Rules

- A claim request for an unlinked profile attaches that profile to the claimant's existing Person only after the configured reviewer approves it, unless a valid invitation policy explicitly authorizes immediate linking.
- An invitation to a known Person links the verified matching account to that Person. It does not reassign or merge profiles.
- A new signup must use its existing Account/Person correctly; never create a duplicate Person for an already-registered account.
- The exact verified-email match is sufficient to accept the Person account invitation, including a manually shared link. Email delivery status may be recorded for operations, but it must not silently add a staff-review requirement.
- Wrong email, unverified email, expired/revoked/used token, ineligible subject, and conflicting linked identity fail safely and without leaking which check failed when that would reveal private information.
- Coach issue/revoke permissions use Phase 2 creator Account ownership.
- A verified recipient may have active invitations for multiple distinct claimable subjects; the active-invitation uniqueness rule is per subject.

## Implementation outline

Extend the existing unified `ClaimInvitation`/`ClaimSubject` design where sound. Avoid parallel invitation services with subtly different status, expiry, digest, or revoke logic. Keep Person invitation semantics because they remain required. Preserve compatibility endpoints only for the documented transition period.

Use stable lock ordering, one-use token digests, expiry, reissue revocation, and transactional claim/invitation state changes. Record issuer, recipient/claimant, reviewer, timestamps, and outcome.

## Acceptance criteria

- Player and coach profiles follow the same auditable lifecycle.
- Known-Person account linking follows verified email matching and preserves profile/history IDs.
- Invitations cannot be replayed or raced into two conflicting links.
- Existing clients continue to work during the planned compatibility window.

## Verification

Cover emailed and manually shared links, matching verified email, unverified/wrong email, existing and new accounts, signup placeholder handling, staff review, owner Coach restrictions, reissue/revoke/expiry, concurrency, and profile-history preservation.

## Implementation record

`ClaimInvitation#verified_email_match?` checks recipient email equality and verification independently of `emailed_at`. Matching but unverified users receive a verification error without consuming the invitation. Matching verified users may link after a manually shared or emailed invitation; invitations with no recipient email remain review requests. A profile invitation can target either a profile without a Person or a profile whose Person has no Account. For a linked Person, the invitation inherits that Person's email and connects the claimant's Account to that existing identity; it does not replace the profile's Person. Redemption creates the Account/Person bridge transactionally for legacy Users without Accounts. Person invitations use the same unified service through both the new and compatibility routes, while old Person invitation tokens remain redeemable through the compatibility service. Old player-profile invitation tokens remain review-only. Redemption rechecks subject eligibility and unclaimed state while holding the subject/invitation locks; claim approval now performs the same recheck, so links and pending claims cannot attach to an archived, connected, or otherwise ineligible identity. Archiving revokes active invitation tokens in the same transaction. Coach placeholders require a display name, matching their model validation. A forward migration removes the global active-recipient email index so one verified email can accept invitations to multiple distinct profiles/People; the existing partial unique index still limits each subject to one active invitation.

The full Rails suite passes; the finalized result and compatibility assertions are recorded in [Phase 11](IDENTITY_225_PHASE_11_FINAL_AUDIT.md).
