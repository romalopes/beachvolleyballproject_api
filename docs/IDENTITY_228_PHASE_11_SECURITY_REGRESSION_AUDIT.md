# Issue 228 — Phase 11: Security, testing and regression audit

## Scope

Audited the Account/profile ownership boundary, claims, invitations, authentication, PII serialization, assessment visibility, and the existing historical-data regression suites. No production rollout was performed.

## Findings and changes

### Fixed: unauthenticated email verification token disclosure

Signup and a pending-verification login previously included the raw email verification token in their JSON responses. A caller could use that value to verify an address without controlling its inbox. The token is now delivered by email only; the service no longer returns it to controller callers, and the API response exposes only a pending state. The SPA already treated pending verification as unauthenticated and did not need the token field.

### Fixed: contact data exposed to profile catalogue readers

Player and coach serializers previously returned linked Person email, phone, date of birth, provenance, and organisation memberships to every authorized profile reader. Those fields are now returned only to an administrator or the Account linked to that profile/Person. Other permitted profile readers receive only the Person's ID and display name fields. Email search is limited to administrators; non-admin name searches no longer match email addresses.

### Fixed: rate limits on public account actions

Rails rate limits now apply per request IP to password login (10 requests per 15 minutes), registration (10 per hour), password reset requests (5 per 15 minutes), and verification resend (5 per 15 minutes). Verification resend also retains its per-account cooldown. Production uses the configured Solid Cache store. Test uses `NullStore`, so integration-level exhaustion behavior is not covered by the current test configuration.

### Fixed: inconsistent anonymous assessment visibility

The assessment relation and row predicate disagreed for anonymous reads of an active assessment on a shared player profile. The row predicate now matches the documented public rule while still excluding private profiles and non-active assessments.

## Existing protections reviewed

- Session login uses the same generic error for unknown email and invalid password; password reset and verification resend use uniform responses.
- Claims require an active Account, supported subject type, profile claimability and service-level locking/uniqueness checks. Claim response summaries redact profile details from claimants.
- Profile mutations ignore client-supplied ownership fields; controller suites cover ownership, visibility, cross-role authorization, invitation approval, and IDOR-style denial cases.
- Invitation redemption validates token state, expiry, verified email, and subject eligibility in the service. Raw claim invitation tokens are returned only at creation/redeem boundaries by their existing design and are not persisted plaintext.
- Profile merging locks both profiles and checks current state and conflicting references within a transaction. Phase 10 documents the reference and deletion matrix.

## Residual findings and limits

- Phase 9 remains partial: Account, organisation/group memberships, training and compatibility endpoints still depend on `Person`/`person_id`. This audit did not drop those columns or tables.
- Registration still responds with a validation error for a duplicate email address, which can reveal whether an address has an Account. Login, reset, and resend do not reveal account existence. Hiding signup uniqueness would change the registration contract and is left as a product/security decision.
- Rails' test cache is `NullStore`, so the new production-backed rate limits cannot be exhausted in current integration tests without introducing a test cache configuration.
- There is no Playwright dependency or browser-test script in the frontend package. Existing Vitest suites and the production build ran instead.
- No production credentials, deployed API, staging database, or real SMTP delivery were available for this audit.

## Commands and results

- `bin/rails test` — **1,489 tests, 6,115 assertions, 0 failures, 0 errors, 1 skipped**.
- Focused auth/profile/assessment suites — **155 tests, 614 assertions** before the final mailer assertion adjustment; the full Rails rerun above includes the final changes.
- `npm test` — **82 files, 875 tests passed**.
- `npm run build` — passed TypeScript and Vite production build. Vite reports the existing JavaScript chunk above 500 kB (about 885 kB).
- `npm run lint` — failed with **4 errors and 1 warning** in the existing `ProfileManagementDashboard.tsx`, `ClaimInvitationPanel.tsx`, and `Identity.tsx` patterns (synchronous state changes inside effects and one missing dependency warning). The new Phase 11 changes do not add a lint finding.
- `bundle exec rubocop --cache false` — **417 files inspected, 480 existing offenses** across the repository.
- Focused RuboCop on the changed controllers/model/test files — **13 files inspected, no offenses**.
- Browser tests: unavailable; no Playwright dependency or browser-test script is configured.

## Status

Security fixes and regression audit are implemented. Phase 11 remains **partially complete** while repository-wide lint debt and the noted integration/runtime checks remain. Phase 12 production rollout remains separate and must not be inferred from this audit.
