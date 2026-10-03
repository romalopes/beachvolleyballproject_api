# Identity Phase 10: Assessment compatibility

## Status

Planned. Existing assessments and assessment sessions reference PlayerProfile and CoachProfile IDs.

## Goal

Verify that claims, multiple profiles, and future Person consolidation preserve all player assessment history and its coach attribution.

## Required behavior

- Assessment history remains attached to PlayerProfile, never Account.
- A claim only links Person to an existing PlayerProfile; it does not move or combine assessments.
- Two PlayerProfiles for one Person retain distinct assessment histories.
- Each assessment/session remains attributed to its original CoachProfile, including after profile multiplicity or Person consolidation.
- Person-level aggregate views, if any, are read-only aggregation and do not rewrite source records.

## Acceptance checks

- Assessment-before-claim then claim retains IDs, scores, status, timestamps, and visibility.
- Multiple profiles for one Person retain separate histories.
- Consolidating Person identities leaves profile-linked assessment data unchanged.
- Authorization and private/draft/withdrawn visibility boundaries still hold.

## Dependencies

Phases 3, 6, and 7. Coordinate with the assessment-specific design docs before changing any assessment schema.
