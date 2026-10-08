# Issue 225 implementation plan status

This plan adapts [GitHub issue 225](https://github.com/romalopes/beachvolleyballproject_api/issues/225) to the current application and later product decisions. Each phase document records the implemented work and any remaining gates.

## Decisions carried into this plan

- A club can record a known Person and their details, or create a profile placeholder with no Person details yet. Keep those workflows available.
- A verified user whose email matches an account invitation can link to the existing Person. Email verification is the ownership check; staff review is not an additional requirement for a copied invitation link.
- A Person can have multiple player and coach profiles; linking a profile must not merge or delete another profile.
- Profile merging, profile deletion, and profile-to-Person linking are separate operations.
- Production migration remains a separate operational phase and is currently blocked by the Phase 14 readiness findings.

## Phase index

| Phase | Scope | Status |
|---|---|---|
| 0 | Repository audit and requirements freeze | Complete; see [audit findings](IDENTITY_225_AUDIT_FINDINGS.md) |
| 1 | Account–Person database integrity | Complete in code and local test/development schema; production-shaped backfill rehearsal remains in Phase 12 |
| 2 | Profile creator Account ownership | Complete in code and local test/development schema; production legacy-row rehearsal remains in Phase 12 |
| 3 | Central profile claimability policy | Complete; org/coach scoping, pending-claim exclusion, privacy, and review policy pass the backend suite |
| 4 | Profile merge and archive lifecycle | Complete in code; migration, reference movement, overlap rejection, and one-winner concurrent merge behavior verified locally. Automated race coverage remains residual risk |
| 5 | Protected-reference hard deletion | Complete; guarded delete, Person retention, and a local delete/reference race diagnostic showed no orphan |
| 6 | Profile invitations and claim behavior | Complete; verified exact-email linking, open-link review, token lifecycle, and per-subject uniqueness pass the backend suite |
| 7 | Legacy claims and invitations transition | Complete for compatibility; reconciliation applied to test/development and read-only readiness is clean. Legacy table retirement remains deferred |
| 8 | People API decision and backend transition | Complete; People workflows retained and covered by the backend suite |
| 9 | Frontend navigation and profile workflows | Complete; 878 frontend tests, lint, TypeScript, and production build pass |
| 10 | Claim and invitation dashboards | Complete; backend/frontend suites pass; manual accessibility review remains recommended |
| 11 | Final integration and security audit | Complete for local code/test databases; 0 failing tests, migration/readiness checks recorded. Production-shaped restore/rehearsal is Phase 12 |
| 12 | Production migration and rollout | Blocked: production target, restorable backup, baseline schema, and deploy host remain unverified |

Read the phase documents in order. Dependencies are listed in each phase. Phases 4 and 6 may proceed after Phase 3 independently, but Phase 5 depends on Phase 4's reference inventory and lifecycle rules. Phases 7–10 depend on the policy and invitation contracts being stable.

## Source material and current implementation

Issue 225 includes a target architecture, 39 design sections, eleven prompts (Tasks 1–10 and final audit Prompt 11), a 33-invariant checklist, and a separate production migration prompt. Phases 0–10 below organize that material around the actual repository rather than replaying already-completed work from Identity Phases 1–18.

Use [IDENTITY_PHASE_STATUS.md](IDENTITY_PHASE_STATUS.md) and [IDENTITY_PHASE_18_UNIFIED_CLAIMS.md](IDENTITY_PHASE_18_UNIFIED_CLAIMS.md) for the existing implementation history. The email-delivery gate is verified exact-email matching; delivery is telemetry only. The Phase 18 document has the implementation record.

## Completion policy

Local completion evidence and remaining operational limitations are recorded in each phase document. Test expectation changes align old assertions to the accepted verified-email, organization-scoped claim, guarded-delete, and creator-account contracts; implementation behavior was not weakened to make tests pass. Do not describe Phase 12 as complete based on a runbook alone; production target confirmation, backup/restore, migration rehearsal, deployment, and post-deploy evidence are required.
