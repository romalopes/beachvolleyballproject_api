# Identity plan phase status

The supplied plan has fifteen phases. Phase 1 is documented in `IDENTITY_PHASE_01_AUDIT.md`; Phase 2 is documented in `IDENTITY_PHASE_02_CARDINALITY.md`. This index records the implementation state of every phase so the audit cannot be mistaken for completion of the whole plan.

| Phase | Work | Status |
|---|---|---|
| 1 | Audit existing identity architecture | Complete; see Phase 1 audit |
| 2 | Person/profile cardinality | Complete for schema, model, API compatibility, and profile context selection; see Phases 6 and 12 |
| 3 | Player claim workflow | Complete for backend/API and interactive claim request/review UI; see Phases 3 and 12 |
| 4 | Candidate discovery | Complete for authenticated suggestions, privacy filtering, API client, and UI |
| 5 | Secure claim invitations | Complete for backend/API lifecycle, single-use safeguards, API client, invitation UI, and focused tests |
| 6 | Multiple CoachProfiles | Complete; see `IDENTITY_PHASE_06_MULTIPLE_COACH_PROFILES.md` |
| 7 | Person consolidation | Complete; focused tests pass and development migration applied; see `IDENTITY_PHASE_07_PERSON_CONSOLIDATION.md` |
| 8 | Account/profile conflicts | Implemented and focused tests pass; two-account conflicts stay blocking; see `IDENTITY_PHASE_08_ACCOUNT_CONFLICTS.md` |
| 9 | Organisation/group validation | Complete; compatibility and authorization integration coverage passes; see `IDENTITY_PHASE_09_ORGANISATION_GROUP_VALIDATION.md` |
| 10 | Assessment compatibility | Complete; claim, profile multiplicity, consolidation, and visibility regression tests pass; see `IDENTITY_PHASE_10_ASSESSMENT_COMPATIBILITY.md` |
| 11 | Identity APIs | Complete; expanded `/me` context, membership write authorization, invitation status, consolidation client methods, and focused tests; see `IDENTITY_PHASE_11_API.md` |
| 12 | Frontend identity UI | Complete; identity context, claim/invitation workflows, coach profile attribution selection, and admin consolidation UI; see `IDENTITY_PHASE_12_FRONTEND.md` |
| 13 | Security audit | Complete; identity endpoint authorization reviewed, invitation tokens moved to URL fragments, and malicious-request regression suites pass; see `IDENTITY_PHASE_13_SECURITY_AUDIT.md` |
| 14 | Production migration | Runbook and read-only report complete; rollout is blocked by the missing `player_coaches` table, no backup in the active R2 prefix, unconfirmed database target, and placeholder Kamal host/registry configuration. See `IDENTITY_PHASE_14_PRODUCTION_MIGRATION.md` |
| 15 | Full business integration matrix | Complete; cross-controller route walkthroughs and named scenario map added. Full backend and frontend suites pass; see `IDENTITY_PHASE_15_INTEGRATION_MATRIX.md` |

## Completion gate

The implementation and integration matrix are complete, and their backend/frontend suites pass. Do not describe the identity system as production-ready until Phase 14's live-target, verified-backup, migration, and post-migration validation gates have passed. The numbered plan is followed here: Phase 6 (CoachProfiles) follows Phase 5 (invitations), even though the supplied implementation-order diagram places coach multiplicity earlier. Phases 7–8 provide safe Person consolidation with blocking Account conflicts and explicit audited membership resolution.
