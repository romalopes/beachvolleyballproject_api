# Player claim workflow (Phase 3)

## Delivered

- Added `player_profiles.display_name` so staff can record a player before a canonical Person exists. Personless profiles require a display name, appear in the player catalogue, and can be searched by that name.
- Added `PlayerClaim` with claimant Person, initiating Person, optional reviewing Person, pending/approved/rejected/cancelled status, review time, and rejection reason.
- Added a transaction-backed `PlayerClaimService`. It locks the profile/claim, permits one pending claim per profile, checks the profile is active and unlinked, and on approval changes only `PlayerProfile.person_id`.
- Added authenticated API endpoints: `GET/POST /api/v1/player_claims`, `GET /api/v1/player_claims/:id`, and member `approve`, `reject`, and `cancel` actions.
- A requester's Person is derived from their authenticated account; submitted identity IDs are ignored. The requester must have a linked, active Person.
- Coaches can review claims only for profiles they recorded. Admins can review any pending claim. A claimant cannot review their own request. A claimant can view/cancel only their own claim. Unauthorized member lookups are concealed as 404s.
- Claim responses for claimants omit the player display name. Reviewer lists show only the display name and claim metadata, with no contact information.
- Approval retains the same profile ID and leaves assessments, training participation, and other profile-keyed history attached to the same row. Claims cannot delete profiles.
- Added TypeScript claim types and API client calls. Existing player pages can render an unlinked profile and avoid showing Person contact fields; the interactive claim request/review screens remain Phase 12 work.

## State changes

```text
pending ── approve ──> approved   (profile.person_id is assigned)
pending ── reject ───> rejected   (profile remains unlinked)
pending ── cancel ───> cancelled  (profile remains unlinked)
```

Reviewed states cannot be replayed. Rejection requires a reason. A partial unique database index prevents concurrent pending claims for one profile.

## Migration

`20261003000002` adds the display name and claim table, foreign keys, status check, and pending-claim index. `20261003000003` restores the invariant that CoachProfiles require a Person; it corrects the local schema after the Phase 2 migration was first applied with coach nullability enabled. Production rollout still requires Phase 14's data inspection and deployment procedure.

## Phase boundary

Candidate discovery is not included (Phase 4). A claimant must already know the profile ID; the API does not search for likely matches or claim profiles automatically. Invitation-based claims are not included (Phase 5). The web UI does not yet provide claim/review controls (Phase 12).

## Verification

The backend suite passes: 1,331 tests, 5,283 assertions, 0 failures, 0 errors, 1 existing skip. Frontend tests pass: 850 tests across 76 files. The production build passes with the existing large-chunk advisory.
