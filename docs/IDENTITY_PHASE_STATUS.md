# Identity plan phase status

The supplied plan has fifteen phases. Phase 1 is documented in `IDENTITY_PHASE_01_AUDIT.md`; Phase 2 is documented in `IDENTITY_PHASE_02_CARDINALITY.md`. This index records the implementation state of every phase so the audit cannot be mistaken for completion of the whole plan.

| Phase | Work | Status |
|---|---|---|
| 1 | Audit existing identity architecture | Complete; see Phase 1 audit |
| 2 | Person/profile cardinality | Complete for backend schema/model/API compatibility; explicit UI context selection remains in Phase 12 |
| 3 | Player claim workflow | Not implemented. Requires claim lifecycle, authorization, conflict handling, and profile naming independent of Person |
| 4 | Candidate discovery | Not implemented. Existing duplicate suggestions are Person-level only and are not a claim authorization mechanism |
| 5 | Secure claim invitations | Not implemented. No claim token/invitation model or redemption endpoint exists |
| 6 | Multiple CoachProfiles | Backend cardinality enabled in Phase 2. Coaching context ownership/selection still needs API and UI work |
| 7 | Person consolidation | Not implemented. Existing `merged` fields are not a consolidation workflow |
| 8 | Account/profile conflicts | Not implemented. Conflict policy and user-facing resolution are needed before consolidation |
| 9 | Organisation/group validation | Not implemented as a dedicated identity regression phase. Current membership relations are Person-based |
| 10 | Assessment compatibility | Not implemented as a dedicated regression phase. Assessments still reference profile IDs and need consolidation-preservation coverage |
| 11 | Identity APIs | Partially compatible only: profile summary includes plural IDs and admin promotion can create more profiles. Claim and consolidation endpoints do not exist |
| 12 | Frontend identity UI | Not implemented beyond additive TypeScript fields for plural IDs. Existing screens still use singular profile IDs |
| 13 | Security audit | Not implemented for new claim/consolidation workflows; those workflows are not available |
| 14 | Production migration | Local schema migration was applied and verified. Production data inspection, rollout procedure, and post-migration validation are not implemented |
| 15 | Full business integration matrix | Not implemented. Current suite passes, but it does not cover the plan's claim/invitation/consolidation scenarios |

## Completion gate

Do not describe the identity plan as fully implemented until every phase above is complete, its own documentation records the implementation and risks, and its phase-specific tests pass. Phases 3–5 should precede a production claimable-profile workflow; Phases 7–8 should precede person/account consolidation; Phases 11–15 should follow the finalized domain and conflict rules.
