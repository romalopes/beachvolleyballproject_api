# Issue 225 — Phase 6: Profile claims and invitations

**Status:** Planned. Depends on Phases 0–3. Preserve Person account-linking behavior per the later product decision.

## Objective

Make profile claims and invitations use consistent rules for PlayerProfile and CoachProfile, while retaining the distinct operation that connects an Account to a known Person.

## Rules

- A claim request for an unlinked profile attaches that profile to the claimant's existing Person only after the configured reviewer approves it, unless a valid invitation policy explicitly authorizes immediate linking.
- An invitation to a known Person links the verified matching account to that Person. It does not reassign or merge profiles.
- A new signup must use its existing Account/Person correctly; never create a duplicate Person for an already-registered account.
- The exact verified-email match is sufficient to accept the Person account invitation, including a manually shared link. Email delivery status may be recorded for operations, but it must not silently add a staff-review requirement.
- Wrong email, unverified email, expired/revoked/used token, ineligible subject, and conflicting linked identity fail safely and without leaking which check failed when that would reveal private information.
- Coach issue/revoke permissions use Phase 2 creator Account ownership.

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
