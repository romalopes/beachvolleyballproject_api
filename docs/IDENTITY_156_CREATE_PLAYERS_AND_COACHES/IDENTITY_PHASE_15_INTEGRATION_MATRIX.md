# Identity Phase 15: End-to-end integration matrix

## Status

Implemented. The matrix now includes cross-controller walkthroughs and maps the identity business scenarios to backend and frontend test cases. Full backend and frontend suites passed on 2026-10-04. Phase 14's production rollout gate remains separately blocked; no production migrations were run.

## Scenario matrix

| Scenario | Coverage |
| --- | --- |
| Person, Account, PlayerProfile, and CoachProfile cardinality; profileless People; multiple profiles with stable profile IDs | `test/controllers/api/v1/players_controller_test.rb` (`create player permits another profile for the same person`, `create can record an unlinked player profile with a display name`); `test/controllers/api/v1/coaches_controller_test.rb` (`a Person may have multiple independently addressable coach profiles`, `archiving one coach profile leaves its Person and sibling profiles intact`); `test/models/person_test.rb` |
| Candidate discovery through claim review; preserve the existing profile and assessment IDs when ownership is approved | `test/integration/identity_business_matrix_test.rb` (`claim discovery, review, and approval link the existing profile without rewriting assessment history`); `test/controllers/api/v1/player_claims_controller_test.rb` (candidate visibility, approval, cancellation, and duplicate pending requests) |
| Invitation issue, redemption, expiry, revoke, replay, ownership, and token privacy | `test/controllers/api/v1/player_claim_invitations_controller_test.rb` (`user redeems a valid invitation into a pending claim without linking or creating a Person`, `used invitations cannot be replayed`, `invalid tokens receive the same generic response as expired and revoked invitations`, `invitation status is concealed from unrelated coaches`) |
| Multiple coach profiles, account and membership preservation, and assessment attribution to a selected profile | `test/integration/identity_business_matrix_test.rb` (`a person with multiple coach profiles can attribute an assessment to the selected profile`); `test/controllers/api/v1/assessments_controller_test.rb` (own-profile attribution and `mine` visibility) |
| Person consolidation across profile, assessment, organisation, group, and alias records; retain all historical IDs | `test/integration/identity_business_matrix_test.rb` (`admin consolidation preserves profile, assessment, membership, group, and alias record ids`); `test/services/identity_assessment_compatibility_test.rb`; `test/services/identity_organisation_group_compatibility_test.rb` |
| Two-Account and duplicate-membership conflicts; explicit, reasoned resolution; atomic rollback and audit provenance | `test/services/person_consolidation_service_test.rb` (`two accounts and duplicate memberships are reported and block all writes`, `explicit membership resolution keeps the selected rows and audits discarded snapshots`, `audit failure rolls every reassignment back`); `test/controllers/api/v1/person_consolidations_controller_test.rb` (`admin receives conflict preview and no partial consolidation`, `explicit membership resolution is admin-only and audited`) |
| Organisation/group compatibility and cross-boundary authorization | `test/controllers/api/v1/groups_controller_test.rb` (`being a group member does not grant organisation membership authority`, `a person outside the group's organisation cannot be added to it`, `a person inside the group's organisation can be added to it`); `test/services/identity_organisation_group_compatibility_test.rb` |
| Assessment-history preservation and original coach attribution across consolidation | `test/integration/identity_business_matrix_test.rb` (`admin consolidation preserves profile, assessment, membership, group, and alias record ids`); `test/services/identity_assessment_compatibility_test.rb` (`multiple player profiles keep distinct assessment histories through consolidation`); `test/controllers/api/v1/assessments_controller_test.rb` |
| IDOR, private-profile visibility, enumeration, invitation replay, and token privacy | `test/controllers/api/v1/player_claims_controller_test.rb` (private candidate exclusion, unauthorized review, and safe response tests); `test/controllers/api/v1/player_claim_invitations_controller_test.rb` (generic invalid-token response and unrelated-owner concealment); `test/controllers/api/v1/player_coaches_controller_test.rb` (`a private player does not become visible through their roster row`); `test/controllers/api/v1/players_controller_test.rb` (`show is 404 for a coach who cannot see a private player`) |
| Frontend identity display, suggestion selection, invitation redemption, login handoff, and consolidation conflict blocking | `../beachvolleyballproject/src/pages/Identity.test.tsx`; `../beachvolleyballproject/src/api.test.ts`; `../beachvolleyballproject/src/pages/PlayerDetail.test.tsx`; `../beachvolleyballproject/src/pages/CoachDetail.test.tsx` |

The new integration tests exercise real Rails routes and persistence. They compare the original assessment attributes and record IDs after a claim approval or consolidation, and assert that Account, sibling profiles, organisation memberships, group memberships, and aliases remain attached to the intended Person.

## Verification

- Backend: `bin/rails test` — **1,386 tests, 5,601 assertions, 0 failures, 0 errors, 1 skip**.
- Frontend: `npm test` — **79 files, 862 tests passed**.
- The three new Phase 15 route walkthroughs also passed independently (**3 tests, 32 assertions**).

The one skipped backend test is the existing `TrainingSessionTest` case at `test/models/training_session_test.rb` requiring a non-manager participant fixture; it is unrelated to identity. No failures required classification, and no identity assertion was weakened to make the matrix pass.

## Production boundary

Phase 15 passing establishes test coverage, not production readiness. Phase 14 still requires a confirmed production target, a fresh verified backup, reconciliation of the missing `player_coaches` table, migration execution, and a clean post-migration readiness report. See `IDENTITY_PHASE_14_PRODUCTION_MIGRATION.md`.
