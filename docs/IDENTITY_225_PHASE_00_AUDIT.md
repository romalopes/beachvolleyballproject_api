# Issue 225 — Phase 0: Repository audit and requirements freeze

**Status:** Complete; findings are recorded in [IDENTITY_225_AUDIT_FINDINGS.md](IDENTITY_225_AUDIT_FINDINGS.md).

## Objective

Establish an evidence-based baseline and record the product rules that later phases must preserve. Issue 225 contains extensive prompts and design sections; this phase adapts them to code that has already evolved through Identity Phase 18.

## Audit scope

Inspect both the Rails API and React/Vite application. Trace:

- Account, User, Person, PlayerProfile, CoachProfile, PlayerCoach, group and organisation memberships.
- Every training, tournament, assessment, ranking, roster, and audit reference to either profile type.
- `player_claims`, `claim_invitations`, and legacy claim/invitation tables, including polymorphic Person subjects and pending records.
- Profile creation attribution, role checks, ownership checks, candidate discovery, invitation issue/redeem/revoke, and relevant routes.
- Singular profile readers and client assumptions that a Person has at most one profile of a type.
- The production readiness task, schema history, migration deployment order, backup process, and Phase 14 blockers.

Record the finding with file/line references and distinguish verified facts from inferences. Produce explicit keep/remove lists for People pages and endpoints, legacy claim APIs, model compatibility methods, and tables.

## Requirements to freeze

1. Keep the club's ability to record known People and connect profiles to them.
2. Keep the no-details placeholder profile path.
3. A verified account with the invited email may connect to the invited Person, including when a coach shares the link manually.
4. Linking does not consolidate profiles. Multiple same-kind profiles may be valid.
5. A coach's invitation authority is based on explicit profile creator ownership, not incidental visibility.
6. Do not remove People functionality unless an equivalent replacement preserves known-Person entry and profile linking.
7. Profile merging and hard deletion require explicit audited operations and must preserve protected history.

## Deliverables

- Audit report covering the scope above.
- ER and domain-reference diagrams.
- Complete profile reference inventory with delete/reassign behavior.
- Singleton-assumption call-site inventory.
- Migration/data risks and unresolved decisions.
- The approved keep/remove list used by Phases 7–9.

## Acceptance criteria

- Every issue 225 invariant maps to an existing implementation, a future phase, or an explicit rejected/changed requirement.
- No destructive migration is proposed without a record-level conversion rule and rollback/recovery analysis.
- Phase 14 production blockers are copied accurately, not treated as resolved by this audit.

## Checks

Read-only schema/model/controller/route searches and existing test inspection were completed. The audit identified an unsafe cascading `training_session_participants` association; Phase 5 changed it to restrictive deletion and included JSON ranking snapshots in the blocker. Full reference and migration rehearsals remain Phase 11 gates. No production mutations were performed.
