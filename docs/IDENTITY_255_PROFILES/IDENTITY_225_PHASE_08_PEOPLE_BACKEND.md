# Issue 225 — Phase 8: People backend and API transition

**Status:** Implemented and verified by the full backend suite. People routes and workflows remain available. Depends on Phase 0 and Phases 3, 6, and 7. Default product direction is to retain People support.

## Objective

Align backend Person endpoints with the agreed workflows: record known people, attach player/coach profiles to existing people, and link verified accounts to known people. Do not remove `/people` merely because the original issue assumed People could only come from Accounts.

## Scope

- Review People index/search/create/update/delete, promotion, consolidation, and nested invitation routes.
- Keep Person lookup/create endpoints required by the player/coach profile forms and staff catalogue.
- Ensure Person deletion is blocked when accounts, profiles, memberships, claims, invitations, or consolidation audits depend on it.
- Retain Person consolidation audit and policy; do not delete those routes/services until a separately accepted replacement exists.
- Remove or alias only endpoints made redundant by Phase 6/7, with deprecation and usage evidence.
- Update production readiness required-table/report logic only after a table is actually retired through a data-retention-approved migration.

## Conditional removal path

If product requirements later explicitly retire `/people`, first design and ship replacement workflows for known-Person entry, profile linking, account invitations, memberships, and administration. Keep internal lookup endpoints needed for those flows. Removal is a later decision, not an automatic consequence of this issue.

## Acceptance criteria

- Staff can still record and find known People and connect profiles without creating duplicate identities.
- Account and profile invariants are enforced by the API, not only by frontend checks.
- Sensitive Person data is scoped to authorized callers.

## Verification

Request tests for create/search/link/update/delete blockers, access control, duplicate handling, profile promotion, consolidation, and existing frontend API contracts. Search all routes and callers before removing any endpoint.

## Implementation record

- `/people` lookup, create, update, delete-blocker, promotion, and consolidation routes remain in place, preserving known-Person recording and profile attachment workflows.
- The nested `account_invitations` compatibility routes now use the unified invitation service and `claim_invitations` records. Only an admin or the recorded Person creator can list, issue, or revoke the invitation. A matching verified email links the Account; Person and profile history remain attached.
- No People routes or Person consolidation records were removed. Production migration/readiness logic was not changed because the old tables remain during the compatibility window.
- `PeopleController` retains authentication and content-creator authorization for lookup/create/update, admin-only delete/promotion, canonical-person filtering, bounded search, and nested membership authorization. `PersonDeletionBlocker` prevents deletion when account, profile, squad or organisation membership, claim/invitation, or consolidation history exists; associations provide a restrictive backstop. Both group and organisation memberships now use restrictive deletion behavior so Person removal cannot erase membership history.
- Final verification: the complete backend suite passed 1,429 runs and 5,796 assertions with no failures or errors. An earlier sandboxed targeted attempt could not access the PostgreSQL socket; it was superseded by the successful authorized full-suite run recorded in [Phase 11](IDENTITY_225_PHASE_11_FINAL_AUDIT.md).
- Sensitive contact details are present in `identity_summary`; access remains limited by the content-creator gate, and the typeahead is capped at 25 rows. This is an intentional staff catalogue contract, not public search.
