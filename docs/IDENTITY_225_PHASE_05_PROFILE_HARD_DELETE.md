# Issue 225 — Phase 5: Protected-reference hard deletion

**Status:** Implemented and exercised by the full backend suite. Protected PlayerProfile/CoachProfile history returns a blocker response, and People deletion authorization/blocker behavior is covered. Rollback-only diagnostics verified successful deletion of an unused profile, refusal to delete a Person with an organisation membership, and a delete-versus-participant-insert race with no orphan. Automated race coverage remains absent. Depends on Phase 4's reference inventory.

## Objective

Add a narrowly guarded hard-delete capability only for profiles with no protected history or audit references. This is a new capability; current player/coach APIs do not expose profile deletion.

## Reference guard

Build a reviewed, explicit inventory of actual associations and foreign keys for both profile types. Do not treat reflection alone as the safety proof. At minimum inspect assessments, training and assessment participants, player-coach relationships, ranking/consolidation records, claims/invitations, group and organisation paths, and any tournament/schedule tables found in the repository. Return a stable blocker list without exposing unrelated private data.

Keep database foreign keys and `restrict_with_error` behavior as a final safety layer. Never use cascading deletion for protected history. A claim or invitation may itself be audit history and should block deletion unless a separately reviewed retention rule says otherwise.

## Permission matrix

- Admin: any eligible profile within the documented application scope.
- Curator: eligible profiles within the curator's authorized scope.
- Coach: eligible profiles created by that Coach's Account only.
- Player/ordinary User: cannot hard-delete profiles.

## Acceptance criteria

- Backend authorization and reference checks run transactionally and cannot be bypassed by direct requests.
- A blocked delete leaves all rows unchanged and reports actionable reference categories.
- A successful delete is limited to truly unreferenced profiles and records an audit event if the application audit policy requires it.

## Verification

Test every role against owned, unowned, and protected profiles; test each protected reference type; test concurrent reference creation versus deletion; verify database restrict behavior. No production deletion is part of this phase.

## Implementation record

Added `ProfileDeletionBlocker` and `DELETE /players/:id` / `DELETE /coaches/:id`. Admins may delete eligible records, Coaches only their own, and Curators must own the record or share an active organisation with its creator. Users with both Coach and Curator roles receive the union of those scopes. Player training participants now use `restrict_with_error`; participant, assessment, coaching, ranking, claim, invitation, JSON ranking snapshot, merge-audit, and merge-lifecycle references block deletion. Schema is applied to local test and development databases. Existing tests exercise protected-history refusal and People deletion authorization; the old absent-route expectation was updated to check `422` with blocker categories. Rollback-only development diagnostics confirmed that unused-profile deletion succeeds, organisation membership blocks Person deletion, and a concurrent participant insert is rejected when deletion wins the profile lock; no orphan row remained. Race automation is not yet part of the suite.
