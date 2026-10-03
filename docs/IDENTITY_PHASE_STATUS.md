# Identity plan phase status

The supplied plan has fifteen phases. Phase 1 is documented in `IDENTITY_PHASE_01_AUDIT.md`; Phase 2 is documented in `IDENTITY_PHASE_02_CARDINALITY.md`. This index records the implementation state of every phase so the audit cannot be mistaken for completion of the whole plan.

| Phase | Work | Status |
|---|---|---|
| 1 | Audit existing identity architecture | Complete; see Phase 1 audit |
| 2 | Person/profile cardinality | Complete for backend schema/model/API compatibility; explicit UI context selection remains in Phase 12 |
| 3 | Player claim workflow | Complete for backend/API and player profile naming; interactive claim screens remain in Phase 12 |
| 4 | Candidate discovery | Complete for authenticated backend/API suggestions and frontend API client; interactive UI remains in Phase 12 |
| 5 | Secure claim invitations | Not implemented. No claim token/invitation model or redemption endpoint exists |
| 6 | Multiple CoachProfiles | Backend cardinality enabled in Phase 2. Coaching context ownership/selection still needs API and UI work |
| 7 | Person consolidation | Not implemented. Existing `merged` fields are not a consolidation workflow |
| 8 | Account/profile conflicts | Not implemented. Conflict policy and user-facing resolution are needed before consolidation |
| 9 | Organisation/group validation | Not implemented as a dedicated identity regression phase. Current membership relations are Person-based |
| 10 | Assessment compatibility | Not implemented as a dedicated regression phase. Assessments still reference profile IDs and need consolidation-preservation coverage |
| 11 | Identity APIs | Partially implemented: plural profile IDs/admin promotion from Phase 2 and claim/candidate endpoints from Phases 3–4; consolidation endpoints remain |
| 12 | Frontend identity UI | Partial support: claim/candidate API client and unlinked player rendering are present; interactive claim and profile-context selection remain |
| 13 | Security audit | Not implemented for new claim/consolidation workflows; those workflows are not available |
| 14 | Production migration | Local schema migration was applied and verified. Production data inspection, rollout procedure, and post-migration validation are not implemented |
| 15 | Full business integration matrix | Not implemented. Current suite passes, but it does not cover the plan's claim/invitation/consolidation scenarios |

## Completion gate

Do not describe the identity plan as fully implemented until every phase above is complete, its own documentation records the implementation and risks, and its phase-specific tests pass. Phases 4–5 should precede a production claim-discovery and invitation experience; Phases 7–8 should precede person/account consolidation; Phases 11–15 should follow the finalized domain and conflict rules.
