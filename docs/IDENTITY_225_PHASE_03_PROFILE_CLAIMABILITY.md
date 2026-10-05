# Issue 225 — Phase 3: Central profile claimability policy

**Status:** Planned. Depends on Phase 0 and Phase 2.

## Objective

Enforce one consistent backend rule for which player or coach profiles a signed-in person may discover and request to claim. Search visibility and claim authority are separate decisions and must not leak profiles outside the authorized scope.

## Policy

Create a centralized policy/service such as `ProfileClaimability` with explicit inputs (profile, Account, and any required organization context). Reuse existing organisation memberships, group membership rules, and `PlayerCoach` relationships. Do not introduce a new coach relationship if the current domain already has the one the issue requires.

Define and test the issue's “same organisation OR associated coach” rule for both profile types. Define treatment of archived profiles, unlinked profiles, current versus former relationships, admins, curators, creators, and the claimant's own linked profiles. Do not infer permission from matching names or email addresses.

## Integration points

- Candidate discovery and search queries.
- Claim request creation and cancellation.
- Invitation issue, lookup, and acceptance where applicable.
- Coach and player detail APIs and any list endpoint that exposes claimable status.
- Review and approval actions.

Eligibility should be scoped in SQL or a composable relation where practical. The service remains the final authorization guard for state-changing requests.

## Acceptance criteria

- The same policy result is used by UI discovery and every backend mutation.
- Direct API calls cannot claim or enumerate an unrelated profile.
- Existing visibility rules for assessments, training, and organisations do not broaden accidentally.

## Verification

Test same organisation, permitted coach association, former coach, unrelated organisation, unlinked claimant, already-linked profile, admin, curator, and ordinary user. Include request tests proving unauthorized records are not returned, not merely disabled in the UI.
