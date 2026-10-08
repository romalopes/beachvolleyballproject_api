# Issue 225 — Phase 2: Profile creator Account ownership

**Status:** Implemented; migrations are applied to the local test and development databases. Creator Account attribution is covered by the full backend suite; production legacy-row backfill remains unverified. Depends on Phases 0–1.

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

## Implementation record

Added `created_by_account_id` to both profile tables with a migration that backfills through existing User Accounts. Legacy profiles without an Account retain `created_by_id` as their compatibility owner. `ProfileOwnership` now centralizes owner checks, and new player/coach profile creation (including People promotion) lazily creates the creator's Account and Person in the same transaction as profile persistence. Invitation, visibility, and claim-review authorization support both new Account ownership and legacy User ownership. Migration `20261006100002_add_creator_accounts_to_profiles` is applied in local test and development databases; tests verify new creator attribution. Production legacy-row backfill remains part of the Phase 12 rehearsal.
