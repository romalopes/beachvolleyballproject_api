# Issue 225 — Phase 2: Profile creator Account ownership

**Status:** Planned. Depends on Phase 0; follows Phase 1 if Account identity is needed for attribution.

## Objective

Represent the creator/owner required by the issue as an Account identity, so Coach permissions remain correct even as authentication/User implementation changes.

## Scope

- Add nullable `created_by_account_id` references to PlayerProfile and CoachProfile.
- Backfill from each existing `created_by_id` User through that User's Account. Report profiles whose creator has no Account; do not guess or assign the migration operator.
- Keep the User creator field during a compatibility period. Add explicit model methods and a single `ProfileOwnership.owned_by?(profile, account)` rule.
- Stamp ownership from the authenticated server-side Account on create. Never accept creator or owner IDs from request parameters.
- Update serializers and authorization paths to expose only the intended safe ownership information.

## Authorization contract

Admin and Curator access is determined by role and configured scope. A Coach can invite, revoke, or administer only profiles whose `created_by_account_id` is that Coach's Account. Read visibility alone does not grant invitation authority.

## Acceptance criteria

- Backfill counts reconcile with source attribution; unresolved rows are documented.
- All new profiles receive creator Account attribution where the role permits creation.
- Client-supplied ownership IDs are ignored or rejected.
- A different Coach cannot invite or manage a creator-owned profile through direct API requests.

## Verification

Migration tests; profile creation attribution tests; positive/negative authorization tests for Admin, Curator, owner Coach, non-owner Coach, and ordinary User; frontend type/API contract checks after serializer changes.
