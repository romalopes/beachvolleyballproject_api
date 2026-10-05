# Issue 225 — Phase 9: Frontend identity and profile workflows

**Status:** Implemented and verified: all 878 frontend tests pass, ESLint passes, and TypeScript/production build passes. Depends on stable Phase 6–8 APIs.

## Objective

Present the approved identity and profile actions clearly, including known-Person and placeholder paths. Keep the People catalogue and `/people` route while they support the agreed product flows.

## Scope

- Retain or refine the existing People list and create/edit flows.
- On player and coach creation, make the two modes clear: link to a Person the club knows, or create a profile placeholder with no Person details.
- Provide claim request status, token redemption, invitation status, revoke/reissue, and clear success/failure messages.
- Keep invitation tokens in URL fragments or another method that avoids server/referrer logs; never persist raw tokens after creation.
- Remove dead API methods/components only after a replacement exists and backend compatibility is confirmed.
- Improve accessibility, loading, empty, error, expired-link, and permission-denied states.

## Navigation

Organize user actions into profile discovery/claim requests and staff review/invitation management. The exact menu labels may differ, but the user should distinguish “claim a profile” from “connect my account to an existing Person.”

## Acceptance criteria

- A coach/admin can issue an invitation to the intended profile or known Person and understand whether email was sent or a link must be shared.
- A claimant sees whether the result linked immediately or awaits review.
- Profile linking does not imply profile merging or deletion.
- Frontend authorization is treated as presentation only; backend policy remains authoritative.

## Verification

Component and route tests for both creation modes, People management, claim/review, invitation/revoke, token parsing, and accessibility states. Run typecheck, lint, test suite, and production build after implementation.

## Implementation record

- Identity supports typed player and coach suggestions, generic claim requests, typed claim history, invitation redemption outcomes, and legacy account-invitation URL parsing.
- The staff invitation dashboard lists the viewer's unlinked player and coach profiles, accepts an optional recipient email, shows a one-time link, and supports revoke/reissue. An exact verified email links immediately even when the URL is manually shared; an open link creates a review request.
- People still supports known-Person creation/editing and account invitation creation. The one-time account invitation URL and copy action are now visible after creation.
- Profile detail invitation panels use the unified API and explain verified-email versus open-link behavior.
- Archived profiles reload invitation state, display the revoked history, and disable new invitations until restored. The API remains authoritative and revokes active tokens when the profile is archived.
- Updated stale assertions to exercise the current redemption button and the supported invitation flow for profile owners without a linked Person. Final Vitest result: 79 files, 878 passed. ESLint and `tsc -b`/production build pass; Vite emits the existing large-chunk warning (885.53 kB minified).
