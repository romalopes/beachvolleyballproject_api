# Issue 228 — Phase 7: Account profile dashboard

## Status

Implemented. The focused frontend suite and relevant Rails controller suites pass, and the frontend production build passes.

## User-facing behavior

The existing `/identity` page now provides the account profile dashboard using the established authentication context and API client:

- **My PlayerProfiles / My CoachProfiles** continue to show the profiles linked to the current Account, including their current status and available context.
- **Find and claim a profile** supports Player/Coach selection, name search, an active organisation filter when the Account has one, paginated results, and selectable claim suggestions. Candidates remain suggestions; an accessible review step explains that club approval is required before submission.
- Existing pending and approved requests appear beside a candidate as its current claim status, avoiding a second request through the normal dashboard flow. Claim failures still surface the API's conflict message if the state changed after search.
- **My pending claims** shows each request's state and permits cancellation while pending. **Claim and invitation history** includes prior claim decisions and completed, expired, revoked, and declined received invitations.
- **Invitations received** lists invitations addressed to the signed-in User's verified email. A recipient can accept or decline an active invitation. Acceptance links an exact verified recipient immediately; decline is persisted as its own status. Open invitations without a recipient email continue through the existing token redemption flow and staff-review process.
- Loading, empty, and error states are shown for profile discovery. Controls use labels, tab roles, live status/error messages, and navigation landmarks. No recipient token digest or other contact fields are returned in the candidate results.

## API and data changes

### Candidate discovery

`GET /api/v1/player_claims/candidates` now accepts `q`, `organisation_id`, `page`, and `per_page` in addition to `claimable_type`.

- The endpoint still starts from `ProfileClaimability.profiles_for`, so an organisation or coach relationship cannot broaden access beyond the established backend claim policy.
- `q` searches profile display names (or their existing effective-name fallback) using escaped `ILIKE`; short queries under three characters return no results. An empty query preserves name-based suggestions.
- An organisation filter is applied only when the caller has an active membership in that organisation. An invalid or unrelated organisation returns an empty result set.
- Results retain the standard `{ data, meta }` pagination contract and disclose only candidate identity fields needed to choose a profile.

### Recipient invitation actions

- `GET /api/v1/claim_invitations/received` returns at most 100 invitations matching the authenticated User's normalized email. Email verification is required before listing.
- `POST /api/v1/claim_invitations/:id/accept` and `/decline` require an active, unexpired invitation with a specific email address matching the authenticated User's verified address. They do not accept open bearer invitations.
- Both actions lock the claimable subject, invitation, and User in the existing order. Acceptance rechecks subject eligibility and availability while locked, then uses the same linking effect as token redemption. Decline changes the invitation to `declined` and records `declined_at`.
- The new migration `20261006100010_add_declined_state_to_claim_invitations.rb` adds that timestamp and permits the new status in the database constraint. Existing `active`, `used`, `revoked`, and `expired` states retain their meanings.
- Invitation summaries do not serialize the raw token or token digest. A different verified account cannot list or act on an invitation sent to another address.

## Files and compatibility

- The frontend adds a paginated candidate-search API call and recipient invitation actions while preserving the previous candidate helper methods for existing callers.
- The existing Identity route and single authentication source are reused. The private Account ContactDetails screen is unchanged.
- The unified `ClaimInvitation` and `PlayerClaim` models remain in use; no second claim or invitation flow was introduced.
- The detailed plan and phase status index now identify Phase 7 as implemented. Phase 8 remains not started.

## Tests and verification

Added or updated coverage for:

- candidate name search plus organisation filtering and pagination;
- rejecting unrelated organisation filters;
- verified invitation recipient listing, acceptance, and decline;
- mismatched and unverified recipient rejection;
- dashboard search, result pagination, explicit claim confirmation, and invitation acceptance.

Attempted commands:

```sh
bundle exec rails test test/controllers/api/v1/claim_invitations_controller_test.rb test/controllers/api/v1/player_claims_controller_test.rb test/services/claim_invitation_service_test.rb
npm test -- --run src/pages/Identity.test.tsx
```

The frontend Identity and management suites passed (17 tests), and `npm run build` passed with the repository's existing Vite large-chunk warning. The focused Rails claim-invitation and claim controller suites passed (47 tests, 188 assertions, 0 failures/errors), covering the Phase 7 candidate filters and recipient invitation actions. Ruby syntax and diff checks passed.

## Next phase

Phase 8 is implemented; see [IDENTITY_228_PHASE_08_PROFILE_MANAGEMENT.md](IDENTITY_228_PHASE_08_PROFILE_MANAGEMENT.md). Phase 9 remains not started.
