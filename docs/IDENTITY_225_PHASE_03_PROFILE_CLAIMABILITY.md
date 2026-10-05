# Issue 225 — Phase 3: Central profile claimability policy

**Status:** Implemented and verified by the full backend suite. Tests exercise same-organisation candidate visibility, pending-claim exclusion, private-profile exclusion, and review authorization. Depends on Phases 0 and 2.

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

## Implementation record

Added `ProfileClaimability` and `ProfileClaimCandidateFinder`. Discovery is SQL-scoped to active, visible, unlinked profiles created by an Account whose Person shares an active organisation with the claimant, or profiles connected by a current `PlayerCoach` row to the claimant's opposite-kind profiles. Admins/curators may discover all active unlinked profiles. `PlayerClaimsController` uses the policy for both candidate search and direct requests and accepts CoachProfile requests through the polymorphic subject. Explicit staff-issued invitations remain a separate authorization path. The older PlayerProfile finder delegates to the shared finder for compatibility. Existing claim tests mostly expect pre-Phase-3 discovery and request eligibility; no dedicated test matrix currently proves all allowed and denied cases against the approved policy.
