# Issue 228 — Phase 4: Account based profile claims

## Status

Implemented. Claimants are identified by Account. Existing claim routes and the `PlayerClaim` table/model names remain for compatibility; claims continue to target either `PlayerProfile` or `CoachProfile` through the existing polymorphic subject fields.

## Existing behavior reviewed

- Profile claims already used a polymorphic PlayerProfile/CoachProfile subject, but the claimant and reviewer were represented only by Person.
- Candidate discovery was limited to profiles with no Person. This omitted an existing Person record with no Account, even though those profiles also need to be claimable.
- The pending-claim unique index allowed only one pending claim for a profile. That prevented two plausible claimants from being reviewed as competing requests.
- Candidate and claim collection routes returned unpaginated arrays.
- Eligibility already relied on active organisation membership of the profile creator or an ongoing PlayerCoach relationship. The rules also respected profile visibility and did not grant global discovery.
- Phase 5 remains responsible for account linking and reviewer decisions. This phase records Account claimant identity while retaining the existing Person-based review implementation as a compatibility bridge.

## Changes

- Added nullable `claimant_account_id` and `reviewed_by_account_id` references to PlayerClaim. Existing claim rows are backfilled from their claimant/reviewer Person when that Person has an Account. Legacy rows without an Account remain readable.
- Replaced the global one-pending-claim-per-profile index with a partial unique index on `(claimable_type, claimable_id, claimant_account_id)`. One Account cannot submit duplicate pending requests; distinct Accounts can submit competing requests.
- New self-service claims require the authenticated User to have an Account with an active Person. The claimant Account is derived from the session, never accepted from request parameters. The Person ID remains as a compatibility and identity snapshot.
- Candidate eligibility now includes both personless profiles and profiles linked to a Person with no Account. A profile linked to an Account is excluded. Candidate lookup remains limited to active profiles visible to the claimant and to the existing organisation/current-coach relationship rules.
- Pending claims no longer hide a candidate from other eligible Accounts. Competing claims remain separately auditable.
- Candidate and claim collection endpoints accept `page` and `per_page` and return the standard `{ data, meta }` response. Candidate search paginates database relations and caps page size using the shared pagination concern.
- Claim invitation redemption records the claimant Account when it creates a review request. Existing Person claim keys and review flows remain intact for this phase.
- The SPA claim API unwraps the paginated response for the current identity screen while requesting up to 100 rows.

## Eligibility and privacy

- An authenticated Account must have an active Person identity to search or submit a claim.
- A profile must be active, named, and not already linked to an Account. Person-backed profiles are eligible when their Person has no Account.
- Discovery stays constrained to existing rules: active membership in the same organisation as the profile creator, or an active PlayerCoach relationship connecting the claimant's opposite-kind profile. The backend rechecks eligibility on submission.
- Admin and Curator roles do not bypass candidate discovery scope. They still need the same organisation or active coaching relationship; the candidate endpoint never returns a global unclaimed-profile catalogue.
- `visibility` is applied to candidate queries. Private profiles are not revealed by an organisation or coaching relationship if the claimant could not otherwise see them.
- Candidate responses include the profile ID/type, display name, and match type only. Contact details and profile history are not exposed.
- Different Accounts may submit competing claims; the current claim-review policy decides who can review. Phase 5 will move review authority and approval/linking onto Account explicitly.

## API contract

The established Rails route names are retained:

```http
GET /api/v1/player_claims/candidates?claimable_type=CoachProfile&page=1&per_page=20
POST /api/v1/player_claims
GET /api/v1/player_claims?page=1&per_page=20
POST /api/v1/player_claims/:id/cancel
```

Example candidate response:

```json
{
  "data": [
    {
      "id": 42,
      "claimable_type": "CoachProfile",
      "claimable_id": 42,
      "coach_profile_id": 42,
      "display_name": "Alex Clubhouse",
      "match_type": "exact_name",
      "result_type": "candidate"
    }
  ],
  "meta": { "page": 1, "per_page": 20, "total": 1, "total_pages": 1 }
}
```

Example request body (Account is inferred from authentication):

```json
{ "claimable_type": "PlayerProfile", "claimable_id": 42 }
```

## Migration and compatibility

- Migration: `20261006100008_add_account_claimants_to_player_claims.rb`.
- Existing Person IDs and polymorphic claim subjects remain available for old clients and the current review service.
- Migration rollback is marked irreversible: once competing pending requests exist, restoring the former global unique index would discard a valid business state.
- No profile, Person, Account, organisation membership, or PlayerCoach records are rewritten by claim submission.

## Verification

- `bin/rails test test/controllers/api/v1/player_claims_controller_test.rb test/services/player_claim_invitation_service_test.rb test/services/claim_invitation_service_test.rb test/integration/identity_business_matrix_test.rb`: **48 tests, 188 assertions, 0 failures/errors**.
- `npm test -- --run src/api.test.ts src/pages/Identity.test.tsx`: **46 tests, 0 failures**.
- `npm run build`: TypeScript and Vite production build passed.
- `bin/rails db:migrate`: migration applied to the configured development database.

## Completed by Phase 5

- Account-based claim reviewer authorization and `reviewed_by_account_id` writes are implemented in [Phase 5](IDENTITY_228_PHASE_05_CLAIM_APPROVAL.md).
- Approval links the claimant Account to the target profile and resolves competing pending claims with audited outcomes.
- Approval records verification method, reviewer Account/Person, and timestamps. Rejection supports an optional internal reason.
