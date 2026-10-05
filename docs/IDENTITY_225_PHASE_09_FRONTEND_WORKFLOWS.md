# Issue 225 — Phase 9: Frontend identity and profile workflows

**Status:** Planned. Depends on stable Phase 6–8 APIs.

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
