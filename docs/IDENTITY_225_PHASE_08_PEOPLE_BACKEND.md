# Issue 225 — Phase 8: People backend and API transition

**Status:** Planned. Depends on Phase 0 and Phases 3, 6, and 7. Default product direction is to retain People support.

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
