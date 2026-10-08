# Identity Phase 5: Secure claim invitations

## Outcome

Authorized profile owners (coaches) and administrators can issue a single-use invitation for an active, unlinked `PlayerProfile`. The API returns its random URL-safe token exactly once. The database stores only a SHA-256 digest, and management responses expose invitation metadata without the digest or token.

An authenticated recipient redeems the token against their existing active `Person`. Redemption records the recipient and use time, and creates a pending `PlayerClaim`. It does not create a `Person` and does not link the profile. The Phase 3 staff approval step remains the point where `PlayerProfile.person_id` changes.

## Lifecycle and safeguards

- Tokens use `SecureRandom.urlsafe_base64(32)` and SHA-256 digest lookup.
- Invitations expire after seven days, can be revoked, and cannot be reused.
- Only one active invitation may exist per profile; issuing another revokes the previous one.
- Redemption locks the profile and invitation in a consistent order and runs claim creation and invitation consumption in one transaction. Concurrent requests therefore have one winner.
- Invalid, expired, revoked, and used tokens share a generic redemption error.
- Creation is limited to 10 requests per minute and redemption to 20 per minute per request identity.
- Invitation endpoints require authentication. Creation, listing, and revocation require the profile owner coach or an administrator. Redemption requires an active linked Person.
- The raw token is returned only from creation and is filtered from parameter logging. No model serialization includes token data.

## API

- `GET /api/v1/player_claim_invitations?player_profile_id=...` lists safe metadata for the owner/admin.
- `POST /api/v1/player_claim_invitations` issues a token for `player_profile_id`; the response includes `token` once.
- `POST /api/v1/player_claim_invitations/:id/revoke` revokes an active invitation.
- `POST /api/v1/player_claim_invitations/redeem` accepts `token` and creates a pending claim for the authenticated user's Person.

## Verification

Controller coverage exercises valid, expired, revoked, replayed, and invalid tokens; authorization; already-claimed profiles; absence of Person creation; safe responses/logs; and pending-claim semantics. A separate service test races two redemption attempts and asserts exactly one succeeds.

The migration is `20261003000004_create_player_claim_invitations.rb`. A frontend API client is included; invitation and claim screens remain part of Phase 12.

## Later correction

This phase was complete and correct, but for a long time **unreachable**. The UI
could not create a player profile without a `Person`, and an invitation can only
exist against one — so the "Create claim invitation" control never rendered for
any profile a coach could actually record. The list and revoke endpoints added
here were also never called by any screen, so a lost token was unrecoverable.

Both defects, and the fix, are documented in
`IDENTITY_PHASE_16_INVITATION_ACCESSIBILITY.md`.

## Operational note

The local development migration was applied. Production rollout and production data checks belong to Phase 14. The test runner needs local PostgreSQL access; run the invitation controller and service tests in the backend environment.
