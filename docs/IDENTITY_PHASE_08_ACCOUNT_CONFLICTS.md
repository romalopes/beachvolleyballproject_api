# Identity Phase 8: Account and profile conflicts

## Status

Planned.

## Goal

Define and implement explicit conflict handling for Person consolidation when both Persons have Accounts or when their memberships/profiles overlap.

## Required behavior

- One Account plus one accountless Person may be consolidated without transferring or deleting the Account.
- Two Accounts on the source and target are a blocking conflict; never pick a winner or delete either automatically.
- Preserve every PlayerProfile and CoachProfile as a separate row.
- Detect duplicate active organisation/group memberships and define whether they can be ended or reconciled without losing history.
- Return typed conflict details to the administrator and require a separate explicit resolution action where needed.

## Acceptance checks

- Both Account conflict directions are covered.
- Two-Account conflict blocks execution without partial writes.
- Profile and membership duplicates preserve provenance and history.
- Resolution actions are authorized and audited.
- The consolidation preview and execution agree on the exact conflict set.

## Dependencies

Builds on the Phase 7 consolidation preview/service. Detailed conflict policy will be recorded here before implementation and may be adjusted to fit database constraints.
