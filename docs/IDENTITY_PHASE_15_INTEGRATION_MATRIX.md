# Identity Phase 15: End-to-end integration matrix

## Status

Planned.

## Goal

Prove the business scenarios in the identity plan across models, API, permissions, and frontend rather than relying only on isolated unit tests.

## Matrix areas

- Basic Person/Account/Profile cardinalities.
- Multiple player and coach profiles and profileless Persons.
- Claim requests, candidate discovery, and one-time invitations.
- Person consolidation and Account/profile/membership conflicts.
- Organisation/group combinations and cross-boundary authorization.
- Assessment history preservation and original coach attribution.
- IDOR, replay, enumeration, and privacy boundaries.

## Acceptance checks

- Every scenario in the supplied Phase 15 prompt maps to one or more named test cases.
- Backend and frontend suites pass; failures are classified as regression, expected behavior change, defect, or unrelated existing failure.
- Tests assert preservation of source records and historical IDs, not merely successful responses.

## Dependencies

Final gate after Phases 6–14. Do not weaken domain assertions merely to make the suite pass.
