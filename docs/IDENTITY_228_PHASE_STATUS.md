# Issue 228 implementation status

| Phase | Scope | Status | Detailed document |
| --- | --- | --- | --- |
| 1 | Repository and identity audit | Complete | [account_identity_refactor_audit.md](account_identity_refactor_audit.md) |
| 2 | Account schema and backfill | Complete | [IDENTITY_228_PHASE_02_ACCOUNT_SCHEMA.md](IDENTITY_228_PHASE_02_ACCOUNT_SCHEMA.md) |
| 3 | Profile ownership and authorization | Complete | [IDENTITY_228_PHASE_03_PROFILE_AUTHORIZATION.md](IDENTITY_228_PHASE_03_PROFILE_AUTHORIZATION.md) |
| 4 | Account-based profile claim requests and discovery | Complete | [IDENTITY_228_PHASE_04_PROFILE_CLAIMS.md](IDENTITY_228_PHASE_04_PROFILE_CLAIMS.md) |
| 5 | Account-based review, approval, and profile linking | Complete | [IDENTITY_228_PHASE_05_CLAIM_APPROVAL.md](IDENTITY_228_PHASE_05_CLAIM_APPROVAL.md) |
| 6 | Invitations to existing and new Accounts | Complete | [IDENTITY_228_PHASE_06_PROFILE_INVITATIONS.md](IDENTITY_228_PHASE_06_PROFILE_INVITATIONS.md) |
| 7 | Account profile dashboard | Complete | [IDENTITY_228_PHASE_07_ACCOUNT_DASHBOARD.md](IDENTITY_228_PHASE_07_ACCOUNT_DASHBOARD.md) |
| 8 | Profile management dashboard | Complete | [IDENTITY_228_PHASE_08_PROFILE_MANAGEMENT.md](IDENTITY_228_PHASE_08_PROFILE_MANAGEMENT.md) |
| 9 | Remove People workflows | Partially implemented; backend dependency cutover remains | [IDENTITY_228_PHASE_09_PEOPLE_WORKFLOWS.md](IDENTITY_228_PHASE_09_PEOPLE_WORKFLOWS.md) |
| 10 | Profile merging, archiving and deletion | Complete | [IDENTITY_228_PHASE_10_PROFILE_MERGING_ARCHIVING_DELETION.md](IDENTITY_228_PHASE_10_PROFILE_MERGING_ARCHIVING_DELETION.md) |
| 11 | Security and regression audit | Partially complete; security fixes and frontend lint are clean, RuboCop/runtime gaps remain | [IDENTITY_228_PHASE_11_SECURITY_REGRESSION_AUDIT.md](IDENTITY_228_PHASE_11_SECURITY_REGRESSION_AUDIT.md) |
| 12 | Production rollout and cleanup | Runbook/readiness gate implemented; production release is NO-GO | [IDENTITY_228_PHASE_12_PRODUCTION_ROLLOUT_CLEANUP.md](IDENTITY_228_PHASE_12_PRODUCTION_ROLLOUT_CLEANUP.md) |

Phases 1–8 and 10 are implemented. Phase 11 has applied the critical token/PII fixes; frontend ESLint, targeted regressions, and build pass. It remains partial because repository-wide RuboCop and production-like rate-limit/browser checks remain. Phase 12's preflight/reporting gate and release runbook are implemented, but production rollout and Person cleanup remain NO-GO pending verified target, recovery, compatibility, and Phase 9/11 gates. Phase 9 removes the active Person workflows from profile management but is not complete: account, roster, claim, and historical training/assessment dependencies still require a durable identity migration. See the detailed phase audits before production rollout.
