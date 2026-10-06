# Issue #228 — Account-Centric Identity Refactor Audit

**Historical snapshot:** this audit records the pre-cutover model. The current Account↔Person decision is in [Phase 9](IDENTITY_228_PHASE_09_PEOPLE_WORKFLOWS.md): Account and User no longer have Person associations in application code, and migration `20261006100011` removes `accounts.person_id` after backfill. Remaining Person roster/history dependencies are retained.

**Issue:** [#228 — Account-centric identity refactoring plan](https://github.com/romalopes/beachvolleyballproject_api/issues/228)

## 1. Current relationship model

```text
User ── 0..1 Account ── exactly 1 Person
 │                         ├── 0..N PlayerProfiles
 │                         ├── 0..N CoachProfiles
 │                         ├── 0..N OrganisationMemberships
 │                         ├── 0..N GroupMemberships
 │                         ├── 0..N claim/invitation/consolidation records
 │                         └── contact data and aliases
 ├── 0..N Roles (via user_roles)
 └── 0..N Sessions

PlayerProfile ── 0..1 Person
CoachProfile  ── 0..1 Person

TrainingSessionParticipant ── PlayerProfile
Assessment ── PlayerProfile + CoachProfile
AssessmentSession ── CoachProfile (+ Group)
PlayerCoach ── PlayerProfile + CoachProfile
RankingConsolidationRow ── PlayerProfile
AssessmentSessionParticipant ── PlayerProfile
```

The database has a unique index on both `accounts.user_id` and `accounts.person_id`; `accounts.person_id` is required. Thus a User has at most one Account, each persisted Account belongs to one User and one Person, and no two Accounts share a Person. A User can exist without an Account at the schema level. `User#person` is a through association. These facts are enforced in `db/schema.rb`, `app/models/account.rb`, and `app/models/user.rb`.

The current code does **not** match the target diagram in issue #228: Account is currently a bridge to Person, not the canonical identity principal. PlayerProfile and CoachProfile have no `account_id`; their `person_id` is nullable. Multiple profiles of either type may point to one Person. A Person may also have no profiles.

## 2. Current authorization and ownership

- Authentication resolves a `User` from a session. `Current.user` is used throughout controllers and services.
- Roles are stored on `User` through `user_roles` and `roles`; `User#admin?`, `coach?`, and `curator?` query that relationship. Account has no roles or permission overrides today.
- Profile creator attribution is dual during transition: profiles have `created_by_id` (User) and optional `created_by_account_id` (Account). `ProfileOwnership` accepts the existing ownership paths. Neither profile type has a linked owner Account column.
- Organisation and group access is predominantly Person-scoped. `OrganisationMembership` supplies roster roles and ownership; `GroupMembership` stores owner/coach/member relationships. Organisation records also have `created_by_person_id`.
- The plan's “Account is the authorization principal” and Account-based permission rules therefore require an explicit role and policy migration. They cannot be implemented by changing profile foreign keys alone.

Relevant files: `app/models/user.rb`, `app/models/account.rb`, `app/models/role.rb`, `app/models/user_role.rb`, `app/models/person.rb`, `app/models/organisation_membership.rb`, `app/models/group_membership.rb`, `app/models/organisation.rb`, and `app/services/profile_ownership.rb`.

## 3. Person data and dependency inventory

The `people` table contains first/last name, email, phone, date of birth, status, creation source, creator User, merge state and timestamps. `Person` also owns aliases and is used as the reusable identity for people who may have no Account or volleyball profile. Email also exists on User as `email_address`; its authentication meaning must remain distinct from any contact email.

Direct Person foreign keys in the current schema are:

| Table / field | Current purpose | Migration concern |
| --- | --- | --- |
| `accounts.person_id` | Account's required identity bridge | Replace with the approved account contact/identity representation. |
| `player_profiles.person_id`, `coach_profiles.person_id` | Shared profile identity/contact record | Backfill Account ownership only where `Person.account` is verified; accountless profile data still needs a home. |
| `organisation_memberships.person_id` | Organisation roster and role, including accountless members | Cannot map every row to Account; many people have no Account. |
| `group_memberships.person_id` | Squad roster, including accountless coaches, parents and volunteers | Cannot map every row to Account; group history must survive. |
| `organisations.created_by_person_id` | Organisation creator/audit provenance | Preserve creator where no Account mapping exists; do not invent an owner. |
| `person_account_invitations.person_id` | Legacy invitation subject and audit | Migrate subject and actors without losing token/status history. |
| `person_aliases.person_id` | Previous names and recognition | Preserve aliases or migrate them to a supported profile/account audit representation. |
| `person_consolidations.source_person_id`, `canonical_person_id` | Completed identity consolidation audit | Preserve both identities and consolidation evidence. |
| `people.merged_into_id` | Person merge chain | Preserve canonical/redirect history or explicitly translate it to a supported audit record. |
| `player_claims.person_id`, `initiated_by_person_id`, `reviewed_by_person_id` | Claimant, initiator and reviewer identities | Current claim workflow needs redesign around Accounts and linked profiles. |
| `player_claim_invitations.created_by_person_id`, `used_by_person_id` | Legacy invitation issuer and recipient identity | Preserve issuer/recipient audit while unifying invitations. |

Other important identity references are polymorphic rather than ordinary foreign keys:

- `claim_invitations.claimable_type/id` accepts `Person`, `PlayerProfile`, or `CoachProfile`; issuer and redeemer fields currently reference User.
- `player_claims.claimable_type/id` accepts Person/profile subjects, alongside legacy subject columns.
- `profile_merges` is a profile-level audit, while Person consolidation is separate.
- JSON audit/snapshot payloads and serialized API responses may carry Person IDs even when no foreign key exists.

Training participation, assessments, assessment-session participation, coaching periods and ranking rows point directly to profile records, which is useful for preserving those histories. Group and organisation memberships, roles, account invitations and identity consolidations instead depend directly on Person.

Direct profile-history foreign keys are also part of the migration audit:

| Profile | Referencing tables/fields |
| --- | --- |
| PlayerProfile | `training_session_participants.player_profile_id`, `assessment_session_participants.player_profile_id`, `assessments.player_profile_id`, `player_coaches.player_profile_id`, `ranking_consolidation_rows.player_profile_id`; legacy `player_claims.player_profile_id` and `player_claim_invitations.player_profile_id`. |
| CoachProfile | `assessment_sessions.coach_profile_id`, `assessments.coach_profile_id`, `player_coaches.coach_profile_id`. |
| Either profile type | Polymorphic `claim_invitations.claimable_type/id`, `player_claims.claimable_type/id`, and `profile_merges.source_profile_type/id` / `canonical_profile_type/id`; ranking session snapshots also store PlayerProfile IDs in JSON. |

PlayerProfile and CoachProfile also self-reference through `merged_into_profile_id`. Their creator and merge actor references point to User and Account, not Person. Person itself records creator/merge actor User IDs.

Key sources: `db/schema.rb`; `app/models/person.rb`; `app/models/player_profile.rb`; `app/models/coach_profile.rb`; `app/models/player_claim.rb`; `app/models/claim_invitation.rb`; `app/services/claim_subject.rb`; `app/services/profile_claimability.rb`; `app/services/person_consolidation_service.rb`; `app/models/group_membership.rb`; `app/models/organisation_membership.rb`.

## 4. Existing workflows

### Backend

- Registration/session/password recovery retain User as the authentication record. Account creation currently creates a signup Person (`Account#ensure_person`).
- Player/coach CRUD creates or updates a Person and then its profile. Duplicate suggestions use `/people/search`.
- Profile claims are implemented in `player_claims` with Person claimant, initiator and reviewer fields. Candidate discovery derives access from the caller's Person's organisation and coaching relationships.
- Unified `ClaimInvitation` still supports a Person subject (link login Account to Person) as well as profile subjects. Its effects may move an Account from a disposable signup Person to a target Person.
- `PersonAccountInvitation`, `PlayerClaimInvitation`, and compatibility routes/services coexist with the unified workflow.
- Person consolidation reassigns membership/history references and stores a separate audit. It must be reconciled with profile merges, not translated to profile linking.

### Frontend

- The SPA has `/identity`, `/account`, player/coach catalogues and per-profile create/edit/detail flows. There is no active `/people` page route in `App.tsx`; Person CRUD/search remains in the API and is used by profile creation, duplicate suggestions and organisation roster selection.
- `/identity` currently presents the caller's Person and Account context, linked profiles, membership lists, claim requests and claim-invitation redemption.
- `PersonCreatePanel` and `PersonProfileForm` collect Person details. Player/coach detail and edit pages render Person data.
- Auth state remains User-based and includes `account_id`, `person_id`, User roles, and profile IDs. `api.ts` includes Person types and Person endpoints.

Relevant files: `config/routes.rb`, `app/controllers/api/v1/{registrations,sessions,me,people,players,coaches,player_claims,claim_invitations}_controller.rb`, `../beachvolleyballproject/src/App.tsx`, `src/auth/AuthContext.tsx`, `src/pages/{Identity,Account,Players,Coaches,PlayerDetail,CoachDetail,PersonProfileEditPage}.tsx`, `src/components/people/PersonCreatePanel.tsx`, and `src/api.ts`.

## 5. Migration risks and unresolved architecture decisions

1. **Accountless membership identities have no target.** Organisation and group memberships deliberately include people without Accounts and even without player/coach profiles. Account requires a User, and ContactDetails is proposed as Account-owned. A direct Person-to-Account migration would either orphan these memberships, fabricate accounts/users, or discard identity data. Issue #228 does not specify the replacement subject for these rows.
2. **ContactDetails is now required for Accounts, but accountless contact data still has no target.** The approved product direction is exactly one ContactDetails record per Account, containing the current Person personal/contact fields. A profile may point to a Person with no Account, and profile tables currently do not contain first/last name, email, phone, or date of birth. The target for accountless profiles and people without profiles still needs a decision.
3. **Multiple profiles can currently share one Person.** When that Person has an Account, every profile can map to that Account. When it has no Account, profile-by-profile migration preserves the rows but loses their shared identity relationship unless the target adds an explicit unclaimed-identity mechanism.
4. **Role ownership differs from the proposal.** User roles currently authorize requests. Moving them to Account affects login, admin role management, impersonation, policies, tests and session behavior. Issue #228 both says preserve User→Account and calls Account the authorization principal, but does not define role backfill or whether roles remain on User.
5. **Invitation/claim history has Person semantics.** The current polymorphic invitation workflow links Accounts by attaching them to Person and retires signup placeholder Persons. Existing claims identify claimant/reviewer People. These require a transactional migration and an explicit mapping for historical actions.
6. **Organization ownership and access are Person-based.** Changing those references without a replacement for accountless officers and creators can break roster access or erase organizational accountability.
7. **AccountAddress already exists.** Keep postal address fields in AccountAddress and personal/contact fields in ContactDetails; migration must not duplicate address values across both records.
8. **Production cutover is high risk.** There are many restrictive foreign keys and production migration/readiness tooling. Removing Person, changing required `accounts.person_id`, or rewriting membership identities is a contract migration and requires staged verification and explicit approval.

## 6. Recommended mapping and implementation sequence

This is the audited recommendation for review before schema work:

1. Keep User as the authentication principal and retain `User -> Account` 1:0..1. Do not move or duplicate login credentials. Preserve User roles in the first additive migration; separately approve any later role migration.
2. Require exactly one ContactDetails record for every Account. Migrate Account-linked Person contact data into it; keep ContactDetails.email (contact email) independent from User.email_address (login email). Keep AccountAddress for postal address data.
3. Add nullable `account_id` to PlayerProfile and CoachProfile. Backfill only when the existing profile's Person has exactly one verified Account (the current unique constraint makes this deterministic); leave accountless profiles unclaimed. Keep Person references during the expand/switch period.
4. Keep creator attribution separate from linked Account. Backfill creator Account only from a verified `created_by_id -> User.account`; retain null for unknown/missing creators.
5. Do not map organisation/group memberships to Account until the accountless-member representation is approved. A profile subject or a separate membership subject must preserve non-player roles and full audit history.
6. Before removing Person, approve a storage target for accountless names/contact data and for shared identity across accountless profiles. Then migrate each Person foreign key, polymorphic subject, audit actor, JSON reference and API consumer independently, validating row counts and relationship invariants.
7. Only after all API and frontend consumers switch should a separately reviewed contract migration remove Person columns/table. Keep the existing profile-level histories and merge records.

The accountless-membership representation and accountless-contact storage remain unresolved before Person can be removed. The required Account→ContactDetail relationship and separation of contact email from login email are confirmed. Roles remain on User, with Account exposing role predicates for policy use. The current schema alone cannot decide the accountless identity target without a product/domain decision.

Suggested phase sequencing after decisions: additive profile ownership/contact schema; ownership/policy changes; claim and invitation migrations; dashboards; membership/organization identity migration; retire Person workflows; deletion and merge audit; security/regression audit; production rollout; separately approved contract cleanup. Each issue checkpoint remains in force.

### File-by-file sequence (provisional; revise after schema approval)

| Order | Existing files / locations | Intended work |
| --- | --- | --- |
| 1. Expand schema | `db/migrate/*`, `app/models/account.rb`, `app/models/player_profile.rb`, `app/models/coach_profile.rb`, `db/schema.rb` | Add the approved Account/contact/profile links and constraints without dropping Person references. |
| 2. Backfill and validate | `app/services/identity_production_readiness_report.rb`, new idempotent backfill service/task, migration tests under `test/` | Report and backfill only verified User/Account/Person/profile mappings; prove counts and ambiguity handling. |
| 3. Ownership and authorization | `app/models/profile_ownership.rb`, User/Account/role models, profile policies/services, `app/controllers/api/v1/{players,coaches}_controller.rb`, `test/` authorization tests | Resolve authenticated User to Account while preserving or migrating roles per approval; make profile ownership/account access server-enforced. |
| 4. Claims | `app/models/player_claim.rb`, `app/services/{profile_claimability,claim_subject,player_claim_service}.rb`, `app/controllers/api/v1/player_claims_controller.rb`, claim tests | Move claimant/reviewer identity to Account and link approval to profile `account_id`; retain historical claim audit. |
| 5. Invitations | `app/models/claim_invitation.rb`, legacy invitation models/services/controllers, `config/routes.rb`, invitation tests | Make Account the invitee/owner where applicable, preserve token digests and legacy outcomes, and retire Person-specific acceptance only after compatibility. |
| 6. Account and management UI | `../beachvolleyballproject/src/api.ts`, `src/pages/Identity.tsx`, `src/pages/Account.tsx`, `src/components/people/*`, profile detail/create/edit pages and their tests | Add Account-owned profile/claim/invitation views while keeping authorized data scoped. |
| 7. Membership identity migration | `app/models/{organisation,organisation_membership,group,group_membership}.rb`, organization/group controllers, migrations and fixtures/tests; corresponding frontend roster views | Implement the approved replacement subject for people without Accounts/profiles before retiring Person dependencies. |
| 8. Retire Person API/UI paths | `config/routes.rb`, `app/controllers/api/v1/people_controller.rb`, person services/models, `src/api.ts`, `src/components/people/PersonCreatePanel.tsx`, duplicate-search consumers and tests | Remove or compatibly retire each Person workflow only after its replacement ships. |
| 9. Merge/archive/delete and audit | `app/services/person_consolidation_service.rb`, profile merge/deletion services, controllers and tests; identity/deletion docs | Preserve identity and history audit; do not equate linking with merging or deletion. |
| 10. Contract and rollout | New separately approved migration(s), `db/schema.rb`, production runbook/report | Remove legacy columns/table only after staging, row-count, FK, rollback and production approvals. |

The user approved Phase 2 with these boundaries: each Account has one required ContactDetail; its contact email stays separate from User login email; profile ownership Account links are nullable; roles remain on User; accountless roster and profile data stays intact; Person references remain operational. Phase 2 and Phase 3 are documented separately in `IDENTITY_228_PHASE_02_ACCOUNT_SCHEMA.md` and `IDENTITY_228_PHASE_03_PROFILE_AUTHORIZATION.md`. Accountless membership/contact representation must be resolved before Person can be retired.

## 7. Phase 1 verification

- Inspected backend schema, models, migrations references, routes, controllers and identity/claim services.
- Inspected frontend routes, auth context, account/identity/player/coach pages and Person-specific components/API types.
- No test suite was run: this phase is read-only and changes no executable code.
- No production or local database rows were modified.

## 8. Decisions recorded

- Account-linked private contact data moves additively to ContactDetail; contact email and User login email remain independent.
- Roles remain on User during this refactor.
- Accountless organisation/group members and unclaimed profiles remain Person-backed and are preserved until a later approved membership migration.
- Person associations remain in place during Phase 2 and are not contracted.
- Phase 2 implementation and migration verification are documented in `IDENTITY_228_PHASE_02_ACCOUNT_SCHEMA.md`.
