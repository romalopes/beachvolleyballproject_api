# Issue 225 — Phase 10: Claim and invitation dashboards

**Status:** Implemented and verified by the full Rails and frontend suites. Claim and invitation APIs enforce role/ownership scope at request time. Keyboard/screen-reader review remains a manual product check. Depends on Phases 3, 6, 8, and 9.

## Objective

Provide distinct user and staff views for profile discovery, claim requests, and invitations without exposing unauthorized profiles or identity data.

## User-side views

- **Claim Profiles:** searchable player/coach tabs; only profiles the backend says are eligible are returned.
- **My Claims:** pending, approved, rejected, and cancelled requests with timestamps and available follow-up actions.
- **My Invitations:** invitation details and acceptance/revocation state appropriate to the signed-in user. An account invitation identifies the Person being connected and requires a verified matching email.

## Staff-side views

- **Profile Requests:** pending claim queue with claimant, profile type, profile, scope, submission date, and approve/reject controls.
- **Invitations:** issued invitations with subject, recipient, issuer, expiry, delivery state, and revoke/reissue controls.
- Coach views are limited to profiles the Coach owns. Curator/Admin scope is explicit and backend-enforced.
- Preserve reviewer identity, reason, and timestamps in the audit trail.

## Acceptance criteria

- Each row is actionable only when the user is authorized at request time.
- The dashboard does not expose unrelated claimant email/contact information.
- Status changes are reflected without duplicating or losing audit records.
- User-facing copy differentiates pending review from immediate verified-email account linking.

## Verification

Test role-scoped list APIs and UI states, pagination/empty/error states, conflicting concurrent review, and updates after action. Include direct API authorization tests; hiding a row in React is not sufficient.

## Implementation record

- Claim discovery switches between player and coach profiles and submits typed requests. The backend remains the source of eligible suggestions.
- The user's own claim list, pending review queue, approve/reject/cancel actions, and Person consolidation audit panel remain available in Identity.
- Staff can list invitations they issued (Admins see the bounded global list), issue profile invitations to players or coaches, set an optional exact recipient email, copy the returned one-time URL, and revoke an active invitation. The People screen issues Person invitations and exposes the same copyable URL.
- The list API scopes non-admin results to the current issuer and limits the response to 200 rows. Per-subject history remains available through the subject-filtered endpoint.
- Final frontend suite (`npm test -- --run`, 2026-10-06): 79 files, 878 passed. The previous stale assertions were updated to match the shipped workflow.
- Final Rails suite passed 1,429 runs and 5,796 assertions with no failures or errors; role and direct-API authorization cases are included.
- Keyboard/screen-reader review and production-role verification remain outstanding; suite counts alone do not establish those acceptance points.
