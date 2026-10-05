# Issue 225 — Phase 10: Claim and invitation dashboards

**Status:** Planned. Depends on Phases 3, 6, 8, and 9.

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
