# Issue 225 implementation plan status

This plan adapts [GitHub issue 225](https://github.com/romalopes/beachvolleyballproject_api/issues/225) to the current application and later product decisions. It is a proposed implementation plan; creating these documents does not mark any phase implemented.

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
| 1 | Account–Person database integrity | Planned |
| 2 | Profile creator Account ownership | Planned |
| 3 | Central profile claimability policy | Planned |
| 4 | Profile merge and archive lifecycle | Planned |
| 5 | Protected-reference hard deletion | Planned |
| 6 | Profile invitations and claim behavior | Planned |
| 7 | Legacy claims and invitations transition | Planned |
| 8 | People API decision and backend transition | Planned; preserve People by default |
| 9 | Frontend navigation and profile workflows | Planned; preserve People by default |
| 10 | Claim and invitation dashboards | Planned |
| 11 | Final integration and security audit | Planned |
| 12 | Production migration and rollout | Blocked pending Phase 14 gates |

Read the phase documents in order. Dependencies are listed in each phase. Phases 4 and 6 may proceed after Phase 3 independently, but Phase 5 depends on Phase 4's reference inventory and lifecycle rules. Phases 7–10 depend on the policy and invitation contracts being stable.

## Source material and current implementation

Issue 225 includes a target architecture, 39 design sections, eleven prompts (Tasks 1–10 and final audit Prompt 11), a 33-invariant checklist, and a separate production migration prompt. Phases 0–10 below organize that material around the actual repository rather than replaying already-completed work from Identity Phases 1–18.

Use [IDENTITY_PHASE_STATUS.md](IDENTITY_PHASE_STATUS.md) and [IDENTITY_PHASE_18_UNIFIED_CLAIMS.md](IDENTITY_PHASE_18_UNIFIED_CLAIMS.md) for the existing implementation history. Phase 18's email-delivery gate must be reconciled with the verified-email decision above before changing invitation acceptance behavior.

## Completion policy

Mark a phase complete only after its acceptance criteria and checks are satisfied, its standalone document is updated with actual implementation evidence, and any migrations have a rehearsal appropriate to their risk. Do not describe Phase 12 as complete based on a runbook alone; production preflight, backup/restore, migration, and post-deploy evidence are required.
