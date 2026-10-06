# Issue 228 — Phase 6: Invitations for existing and new Accounts

## Status

Implemented for both PlayerProfile and CoachProfile invitations. An invitation may target a verified email address or remain open for staff-reviewed claiming. Phase 7's Account dashboard is now implemented; see [IDENTITY_228_PHASE_07_ACCOUNT_DASHBOARD.md](IDENTITY_228_PHASE_07_ACCOUNT_DASHBOARD.md).

## Existing workflow reused

The codebase already had a unified `ClaimInvitation` for Person, PlayerProfile, and CoachProfile subjects. Phase 6 completes the Issue 228 requirements on this implementation rather than introducing a parallel invitation table:

- Issuance, redemption, revocation, email delivery, and rate limiting were already present.
- The raw token is generated once; only its SHA-256 digest is persisted.
- A verified exact match to the invited email links a profile immediately. An open link creates a Phase 5 claim for staff review.
- Claim eligibility is rechecked while holding locks on the profile and invitation. History and the original profile ID remain intact.

## Changes in this phase

- Profile invitations now allow an authorized issuer to edit or correct a Person-backed profile's recorded email. An explicit recipient email takes precedence over the stored Person email; leaving it blank creates an open invitation that requires review.
- Curators may issue invitations for profiles within the existing oversight scope. Coaches remain limited to profiles they recorded; admins retain oversight. Curators can list invitations within that same profile scope. Person invitations remain under their existing coach/admin policy.
- The detail-page panel exposes the recipient email field for PlayerProfile and CoachProfile invitations. The Identity invitation list also includes Curators and collects invitations without exposing the one-time token after creation.
- The unauthenticated invitation route carries its fragment through sign-in and registration. The app temporarily stores the internal return path in browser local storage while email verification is pending, then restores the user to `/identity#claim_token=…` after verification and sign-in. Successful redemption clears this saved path.
- A new registrant completes the existing registration and email verification flow. Registration now creates the User, Account, and required ContactDetail in one transaction; email verification still gates session creation and acceptance. No User is silently created when staff issue an invitation.
- Existing and newly registered users use the same path: authenticate, verify the login email, and redeem. Legacy Users that predate Account provisioning receive an Account and ContactDetail during acceptance. The service then links immediately for an exact verified-email invitation or submits a claim for review.
- Existing status and column names are retained for compatibility: `active` means pending, `used` means accepted/redeemed, `revoked` means cancelled, and `expired` records expiry. The issuer remains a User foreign key. Invitation issuance deliberately does not look up or store an invited Account ID; binding is to the normalized email and the authenticated verified address, which avoids disclosing whether the address already has an Account.

## Security and lifecycle

- Tokens use `SecureRandom.urlsafe_base64(32)`. Only a digest is saved; raw token values are returned once to the authorized issuer or passed directly to the mailer, and are never included in invitation summaries or logs.
- Links are seven days by default, single-use, revocable, and protected by API rate limits (10 issuance requests and 20 redemption requests per minute).
- Email-specific redemption requires the authenticated User's email to match exactly after normalization and requires `email_verified_at` to be set. A mismatch produces a generic invalid-invitation response.
- Open invitations do not prove identity. They create a pending Account-based claim, which Phase 5 approval must review.
- One active invitation is allowed per subject. Issuing a replacement revokes the prior live link. Historical invitation rows remain available for audit.
- Email delivery is optional and failure-safe. The link remains available for the authorized issuer to copy; no delivery status bypasses email verification.
- Profile row locking and invitation row locking ensure two concurrent redemption attempts cannot consume a link twice.

## API contract

```http
POST /api/v1/claim_invitations
Content-Type: application/json

{
  "claimable_type": "CoachProfile",
  "claimable_id": 19,
  "invitee_email": "new.or.existing@example.com"
}
```

`invitee_email` is optional. The create response contains invitation metadata, a one-time raw token for immediate copying, and `email_delivered`. Subsequent list/show responses never return the token.

```http
POST /api/v1/claim_invitations/redeem
Content-Type: application/json

{ "token": "one-time-secret" }
```

The response has outcome `linked` for an exact verified email match or `pending_review` for an open invitation. The established `/api/v1/player_claim_invitations` endpoint remains as a compatibility route.

## UI flow for a new recipient

1. The recipient opens the invite URL and chooses **Sign in**, then **Create an account**.
2. They register with the invited email. The normal email verification requirement still applies.
3. After verification, they sign in and return to the invitation token already present in the browser.
4. They redeem it. A verified email-bound invite links the profile immediately; an open invite creates a claim for staff approval.

## Verification

- Invitation, model, policy, registration, legacy Person-account, and concurrent-redemption Rails suites: **63 tests, 311 assertions, 0 failures/errors**.
- Identity, Login, Signup, VerifyEmail, ClaimInvitationPanel, PlayerDetail, and CoachDetail frontend suites: **52 tests passed**.
- `npm run build`: TypeScript and Vite production build passed. Vite reports the existing main-chunk-size warning (>500 kB).
- No database migration was needed; the unified invitation schema and token digest index already existed.

## Compatibility and follow-up

- The API and database retain `ClaimInvitation`, `active/used/revoked/expired`, and `invited_by_id` names to preserve existing invitation flows and audit rows.
- Recipient email binding is intentionally used instead of persisting `invited_account_id`; existing and new Account recipients follow the same verified-email rule.
- Phase 7 provides account-level recipient invitation visibility without exposing raw tokens and preserves the current subject-level authorization checks. See [Phase 7](IDENTITY_228_PHASE_07_ACCOUNT_DASHBOARD.md).
