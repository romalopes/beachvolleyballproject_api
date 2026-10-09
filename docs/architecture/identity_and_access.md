# Identity and access

[Architecture index](architecture.md) · [Relationships](model_relationships.md)

## Four different concepts

| Concept | Current responsibility |
|---|---|
| `User` | Login email, password digest, verification state and global roles. |
| `Session` | A user's signed-cookie or bearer-token login session. |
| `Account` | Application identity linked to a user; owns private `ContactDetail` and optional `AccountAddress`. |
| Player/coach profile | Independently named volleyball identity, optionally linked to an account, with participation and assessment history. |

`Account` currently requires a user and uniquely indexes `user_id`. Registration
creates User, Account and ContactDetail in one transaction. The User association is
`has_one :account`; a raw User record is not proof that registration completed.
An account can have multiple player and coach profiles. Staff can create profiles
without an account, allowing participation before signup.

There is no current Person model. The historical
[person identity document](../IDENTITY_228_ACCOUNT_CENTRIC/PERSON_IDENTITY_MODEL.md)
is an earlier design reference; do not implement its old cardinalities without
checking the current models and migrations.

## Authentication and authorization

[Authentication](../../app/controllers/concerns/authentication.rb) first tries a signed
session cookie and then an Authorization bearer token. API tokens have a configured
30-day expiry when created; an expired token's session is destroyed when checked.
`Current` provides request-local access to the resumed session/user.

The test-access password is a separate, optional site gate. Its signed token does
not authenticate a User or grant any application role. Email verification can prevent
new users from receiving login sessions until they verify their address.

Global roles are `Role` records joined to users by `UserRole`. A CoachProfile does
not grant the coach role. Content management includes coach, curator and admin
checks; action-specific controllers and policies remain the authority. Organisation
membership roles and group roles have their own scope and do not become global roles.

## Ownership and privacy

[ProfileOwnership](../../app/services/profile_ownership.rb) distinguishes the linked
account (`account_id`) from the creating account (`created_by_account_id`), with
legacy `created_by_id` support. Both linked and creating identities participate in
ownership checks; claiming does not erase provenance.

[ProfilePolicy](../../app/services/profile_policy.rb), ProfileManagementScope and
ProfileClaimability handle different questions: may this actor view/manage the row,
and is it currently eligible for a claim? A `shared`/`private` flag is not a substitute
for these checks. Contact details belong to Account, not to the public profile name.

Organisation management uses [OrganisationAccess](../../app/services/organisation_access.rb).
Membership can name an Account, PlayerProfile or CoachProfile. Group memberships
are account-based. Do not assume parent-organisation membership grants management
of descendants, or that a member with the local `coach` role manages the roster.

## Linking existing profiles

`PlayerClaim` is the retained class/API name for requests covering both player and
coach profiles. New polymorphic subjects coexist with the legacy player foreign key;
the model requires exactly one subject representation. Approval links the claimant
account to the existing profile through ClaimSubject; it preserves the profile ID
and its history, records reviewer evidence and resolves competing pending claims.

`ClaimInvitation` is another route to linking, using a digest-backed, expiring token
or addressed invitation. ClaimInvitationService checks subject eligibility, recipient
and current state before linking. It records who used it; merely possessing a profile
ID does not claim the profile. See [lifecycles](system_lifecycle.md) for state changes.
