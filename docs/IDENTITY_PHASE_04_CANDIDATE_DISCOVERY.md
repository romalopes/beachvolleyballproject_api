# Player profile candidate discovery (Phase 4)

## Delivered

- Added `GET /api/v1/player_claims/candidates`, requiring authentication and an active Person linked to the signed-in account.
- The finder compares the caller's current full/first/last name and recorded Person aliases with active, unlinked `PlayerProfile.display_name` values. Exact normalized name matches are ranked before partial token matches.
- Only profiles visible under the existing `PlayerProfile.visible_to` policy are considered. Profiles already linked to any Person and profiles with a pending claim are excluded.
- Results are capped at 20, deterministic, and explicitly labeled `result_type: "candidate"` with `match_type: "exact_name"` or `"partial_name"`. The response contains only profile ID and display name. It does not include email, phone, date of birth, owner, notes, assessments, memberships, or claim authority.
- Search uses the caller's own recorded identity fields and aliases; it does not accept arbitrary search text, so the endpoint cannot be used to enumerate the player catalogue by trying names.
- Candidate discovery does not create claims, associate a profile, merge People, or imply identity confirmation. The user must submit a separate claim request and a coach/admin review is still required.
- Added the frontend API client method and candidate type. The search/review interaction UI remains Phase 12 work.

## Matching limits

The current PlayerProfile stores only a display name when it is unlinked, so there are no profile-side email, phone, or birth-date fields to compare. Matching uses the caller's known name strings and aliases against that display name. Results are suggestions and can be incomplete or ambiguous; exact and partial labels describe string matching only, not confidence or proof of identity.

## Verification

Request tests cover exact and partial names, previous-name aliases, no and multiple matches, already linked profiles (including multiple profiles for the same Person), pending claims, private profile visibility, safe response fields, and unauthenticated/no-Person access. Verification passed: 1,340 Rails tests (5,308 assertions, one existing skip), 851 frontend tests, and the production build. Vite reports its existing large-chunk advisory.
