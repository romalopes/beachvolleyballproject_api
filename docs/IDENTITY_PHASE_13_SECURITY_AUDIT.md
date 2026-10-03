# Identity Phase 13: Security audit

## Status

Planned. Phase 5 includes focused token handling and authorization tests; the complete workflow audit remains.

## Goal

Review identity-changing endpoints for account takeover, IDOR, enumeration, token exposure, unauthorized profile access, and organization/group boundary bypass.

## Audit areas

- Player claims and candidate discovery.
- Claim invitation creation, redemption, replay, expiry, revocation, brute force, and logs.
- CoachProfile ownership, attribution, and context switching.
- Person consolidation and Account/profile reassignment.
- Organization/group membership boundaries and sensitive identity payloads.

## Deliverables

- Finding, severity, affected code/endpoint, remediation, and regression test for each issue.
- Fix critical/high-risk defects and document accepted residual risks.
- Malicious request tests that bypass frontend controls.

## Dependencies

Run after Phase 11 API completion and Phase 12 UI contracts are known. Do not treat frontend role checks as security enforcement.
