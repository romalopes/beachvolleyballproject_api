# BeachVolleyballProject — Account-centric identity refactoring plan

The revised architecture preserves the existing **User → Account relationship**, eliminates Person as an intermediate identity layer, and allows each Account to be associated with multiple player and coach profiles.

The responsibilities are:

- **User:** authentication, credentials, login sessions and password recovery.
- **Account:** application identity, roles, permissions and ownership of profiles.
- **PlayerProfile:** a player's volleyball-related identity and history.
- **CoachProfile:** a coach's volleyball-related identity and history.
- **ContactDetails:** required personal and contact information associated with every Account.

Use an incremental migration rather than rebuilding the identity system. Existing training sessions, assessments, tournaments, groups and historical associations must remain intact.

## 1. Repository assessment and architectural decision

| Repository | Stack | Scope |
| --- | --- | --- |
| [beachvolleyballproject_api](https://github.com/romalopes/beachvolleyballproject_api) | Rails API | Models, migrations, permissions, claims, invitations |
| [beachvolleyballproject](https://github.com/romalopes/beachvolleyballproject) | React, TypeScript, Vite | Account screens, profile discovery, approvals, invitations |

**Verification limitation:** The earlier inspection covered public repository summaries, rather than individual model files and the schema. This is an implementation-ready target plan, not a claim that every existing association has been verified. Phase 1 requires the AI coding tool, with access to the local repositories, to inspect the actual code before modifying it. No fresh repository inspection is implied by this document.

## 2. Proposed data architecture

| Relationship | Target cardinality | Meaning |
| --- | --- | --- |
| User → Account | 1:1, subject to audit | Authentication resolves application identity |
| Account → ContactDetails | 1..1 | Required private personal and contact information |
| Account → PlayerProfiles | 0..N | Several player profiles may belong to one Account |
| Account → CoachProfiles | 0..N | Several coach profiles may belong to one Account |
| PlayerProfile → Account | 0..1 | NULL means unclaimed |
| CoachProfile → Account | 0..1 | NULL means unclaimed |

An Account can exist without any volleyball profiles. Several linked profiles represent the same account holder without automatically being duplicates.

### 2.1 Responsibility boundaries

| Model | Responsibility | Important constraint |
| --- | --- | --- |
| User | Credentials, authentication, login security | Preserve existing authentication |
| Account | Identity, roles, permission overrides, ownership | One Account per User, subject to audit |
| ContactDetails | Name, contact preferences, personal information | Exactly one per Account |
| PlayerProfile | Player identity in volleyball contexts | Optional Account; multiple per Account |
| CoachProfile | Coach identity in volleyball contexts | Optional Account; multiple per Account |
| ProfileClaim | Request to link an existing profile | Historical and auditable |
| ProfileInvitation | Invitation to accept a profile | Tokenized and expiring |
| ProfileMerge | Explicit duplicate consolidation | Preserve historical references |

**User is not replaced by Account.** Authentication continues to resolve the current User; application authorization resolves that User's Account.

### 2.2 ContactDetails

Every Account must have exactly one ContactDetails record. Create the Account and ContactDetails together in one transaction, and reject an Account that has no ContactDetails. Enforce one ContactDetails per Account with a non-null, unique `account_id`; use the Account creation/update service to maintain the required inverse association.

ContactDetails receives the personal and contact fields currently held by Person: first name, last name, contact email, phone, date of birth and any other personal/contact fields confirmed in the audit. Keep authentication email on User as a separate value: ContactDetails.email is the contact address and User.email_address remains the login address. Preserve both values independently; do not overwrite one from the other during routine edits. Person lifecycle/merge metadata and aliases are identity/audit data, not ContactDetails fields.

| Field | Type |
| --- | --- |
| account_id | Required foreign key, unique |
| first_name | String, required |
| last_name | String, nullable |
| preferred_name | String, nullable |
| email | String, nullable; contact address, distinct from User login email |
| phone | String, nullable |
| date_of_birth | Date, nullable |
| country_code | String, nullable |
| timezone | String, nullable |

Do not automatically copy private ContactDetails into publicly visible player profiles. Keep AccountAddress responsible for postal address data so it does not duplicate ContactDetails fields.

Rails naming should follow repository conventions: for example, `ContactDetail` / `contact_details`, with `Account.has_one :contact_detail`.

### 2.3 Proposed profile fields

Both profile models should eventually support these identity-linking fields, subject to the existing schema:

```ruby
account_id             # Nullable: linked Account
created_by_account_id  # Original creator
merged_into_id         # Optional, same profile type
merged_at              # Optional
archived_at            # Optional
```

Keep existing organisation, coach, level, membership and other business relationships where they currently belong. Do not add organization ownership columns merely for convenience.

For legacy profiles whose creator is unknown, do not invent an Admin creator. Backfill from reliable audit data or retain a documented nullable legacy exception.

## 3. Business rules

### Profile creation and ownership

A coach may create a player without requiring registration. An Admin or Curator may create profiles within their authorized scope. One Account may own several PlayerProfiles and CoachProfiles; this does not make those profiles duplicates.

| Example record | Linked Account | Original creator | Context |
| --- | --- | --- | --- |
| Maria's PlayerProfile #14 | Maria's Account | Preserved creator | Coogee |
| Maria's PlayerProfile #82 | Maria's Account | Preserved creator | Another coaching context |
| Maria's CoachProfile #19 | Maria's Account | Preserved creator | Coach |
| Unclaimed PlayerProfile #106 | NULL | Account #42 | Coach-created profile |

A profile's creator and linked Account are different concepts. Claiming a profile must not overwrite its creator or volleyball history.

### Permissions matrix

These are proposed defaults. Reconcile actual role names and permission identifiers with the existing authorization implementation.

| Action | Account owner | Coach | Curator | Admin |
| --- | --- | --- | --- | --- |
| View own linked profiles | Yes | — | — | Yes |
| Create profiles | By granted permission | Yes | Scoped | Yes |
| Request eligible claim | Yes | Yes | Yes | Yes |
| Approve claims | No, unless delegated | Scoped | Scoped | Yes |
| Invite to a profile | No, unless granted | Created profiles | Scoped | Yes |
| Cancel invitation | Recipient can decline | Own issued invitations | Scoped | Yes |
| Unlink a profile | Controlled workflow | Scoped only | Scoped | Yes |
| Merge profiles | No by default | No by default | Scoped, if granted | Yes |
| Hard-delete unused profile | No by default | Created profiles | Scoped | Yes |

An Account may be both player and coach. **Owning a CoachProfile does not automatically grant the Coach role or administrative permissions.** Authorization remains separate from profile identity.

Claims should be discoverable only through an established shared organization or coaching relationship. Approval still requires identity evidence or an authorized verification process. A matching name, shared coach or shared organization is not proof of ownership.

**Linking, merging and deleting profiles are separate operations.** Linking a profile to an Account must never automatically delete another profile or any Training, Tournament, Assessment or Ranking history.

## 4. Implementation roadmap

Run the following 12 phases sequentially in the AI coding tool using the existing local repositories.

| Phase | Outcome |
| --- | --- |
| 1 | Read-only architecture audit |
| 2 | Additive schema and validated backfill |
| 3 | Account-based ownership and authorization |
| 4 | Profile claim backend |
| 5 | Transactional claim approval and linking |
| 6 | Existing- and new-account invitations |
| 7 | Account dashboard |
| 8 | Management dashboard |
| 9 | Retire Person and People workflows |
| 10 | Explicit merge, archive and deletion workflows |
| 11 | Full regression and security audit |
| 12 | Production rollout and final cleanup |

## 5. Master instructions for the AI coding tool

Give the agent these instructions first. They apply to every subsequent phase.

```text
# BeachVolleyballProject — Master Refactoring Instructions

You are working with two independent repositories:

Backend:
my_projects/beachvolleyballproject/beachvolleyballproject_api
https://github.com/romalopes/beachvolleyballproject_api

Frontend:
my_projects/beachvolleyballproject/beachvolleyballproject_frontend
https://github.com/romalopes/beachvolleyballproject

## Architecture

Preserve the existing User -> Account relationship.

Target:
- User: authentication, credentials, sessions.
- Account: application identity and authorization.
- Account -> exactly 1 ContactDetails.
- Account -> 0..N PlayerProfiles.
- Account -> 0..N CoachProfiles.
- PlayerProfile.account_id is nullable.
- CoachProfile.account_id is nullable.
- Eliminate Person as a separate canonical identity after safely migrating
  its data and references.

## Mandatory rules

1. Inspect actual code and schema before implementation.
2. Preserve existing authentication, User/Session workflows and role permissions.
3. Never assume User and Account are interchangeable.
4. Trace association consumers before replacing associations.
5. Keep historical training, tournament, assessment, ranking, group and
   schedule records.
6. Never automatically merge profiles.
7. Implement server-side authorization for every operation.
8. Treat Account as the authorization principal.
9. Use transactions, database constraints and row locking where necessary.
10. Avoid N+1 queries and unbounded searches.
11. Write automated tests for all new business rules.
12. Keep the Rails API and React frontend independently deployable.
13. Never expose personal information through public profile search.
14. Follow existing naming, serializer, service and test conventions.
15. Prefer incremental, reversible migrations.
16. Never drop a legacy table or column until a verified backfill and
    dependency audit have succeeded.

## Work protocol

For every phase:
- Inspect relevant files.
- Explain current behavior.
- List proposed modifications.
- Implement only that phase.
- Run relevant tests and static checks.
- Report changed files and test results.
- Identify outstanding risks.
- Stop at the checkpoint and await approval before proceeding.

Do not claim tests passed unless they actually ran successfully.
```

## 6. Phase-by-phase AI prompts

### Phase 1 — Audit the current architecture

The existing User → Account implementation must drive the migration.

```text
# Phase 1 — Read-only Architecture Audit

Inspect both BeachVolleyballProject repositories. Do not modify code.

## Backend

Inspect:
- db/schema.rb or structure.sql
- db/migrate
- app/models/user.rb
- app/models/account.rb
- app/models/person.rb, if present
- PlayerProfile and CoachProfile models or their actual equivalents
- Roles and permission models
- Authentication and session controllers
- Account, People, Player and Coach controllers
- Existing claims and invitations, if any
- Organization, Group, Training, Tournament, Assessment and Ranking relationships
- Routes, serializers, services, callbacks and background jobs
- Tests and fixtures

## Frontend

Inspect:
- Authentication context
- Account context
- Account settings pages
- People pages and routes
- Player and Coach pages
- Organization and Group interfaces
- API clients and TypeScript models
- Navigation and permission guards

## Required output

1. Current entity relationship diagram in plain text.
2. Exact User-to-Account cardinality and foreign-key direction.
3. All existing Person dependencies.
4. Existing PlayerProfile/CoachProfile cardinalities.
5. How roles and permissions are resolved.
6. How profiles are currently created and linked.
7. Every model with foreign keys to Person, PlayerProfile or CoachProfile.
8. Data migration and deletion risks.
9. Recommended final schema based on actual implementation.
10. File-by-file implementation sequence.

Identify whether the project uses Player and Coach instead of PlayerProfile
and CoachProfile. Prefer preserving existing model names unless a rename is
demonstrably necessary.

Produce docs/account_identity_refactor_audit.md.

Do not implement the refactor yet.

STOP: Request approval for the proposed schema and migration mapping.
```

**Checkpoint 1:** Confirm the actual relationships between User, Account and Person, including all dependent foreign keys.

### Phase 2 — Account-centric schema and data migration

Use **expand → backfill → switch reads/writes → validate → contract**. Do not remove Person yet.

```text
# Phase 2 — Account-Centric Data Model

Use the approved Phase 1 audit.

Implement an additive migration toward:
- User -> Account
- Account -> ContactDetails (1..1)
- Account -> PlayerProfiles (0..N)
- Account -> CoachProfiles (0..N)

## Tasks

1. Preserve the existing User/Account relationship and authentication schema.
2. Add required ContactDetails and ensure every Account creation path creates it atomically.
3. Map each Account-linked Person's personal/contact fields into ContactDetails, preserving the existing User login email separately.
4. Avoid duplicated authentication email and inconsistent contact data.
5. Add nullable account_id to PlayerProfile and CoachProfile where missing.
6. Add created_by_account_id with a reliable legacy backfill strategy.
7. Backfill profile account_id using verified Person -> Account relationships.
8. Keep profiles without a verified Account unclaimed.
9. Handle People with missing, duplicate or conflicting User/Account associations.
10. Never arbitrarily select an Account when multiple mappings exist.
11. Add appropriate indexes, foreign keys and uniqueness constraints.
12. Keep legacy Person references operational during transition.

## Migration design

Use small migrations with a repeatable, idempotent data backfill.

Provide dry-run counts:
- Users
- Accounts
- People
- Linked profiles
- Unlinked profiles
- Ambiguous identity mappings
- Profiles with unknown creators
- Orphan foreign keys

Write a validation task comparing before/after counts and checking that no
historical domain references disappeared.

Do not use destructive cascading deletes.

## Tests

Cover:
- Account without profiles
- Account with multiple PlayerProfiles
- Account with multiple CoachProfiles
- Account with both types
- Unclaimed profiles
- Orphan and ambiguous legacy Person mappings
- Idempotent backfill
- Existing login and password recovery

Do not drop Person or its columns in this phase.

STOP: Provide migration verification results.
```

**Checkpoint 2:** New associations work while legacy data remains available.

### Phase 3 — Profile ownership and authorization

Separate original creator, linked Account and organizational/coaching scope.

```text
# Phase 3 — Profile Ownership and Authorization

Use Account as the application authorization principal, preserving User
authentication.

## Ownership

Each profile may have:
- account_id: linked Account, nullable.
- created_by_account_id: original creator.
- Existing organization and coaching relationships.

Do not infer creator from current owner.

## Permission rules

- Admin: administrative bypass only after authentication and applicable
  tenant/scope rules have been evaluated according to the approved policy.
- Curator: actions restricted to permitted organizations/scopes.
- Coach: create profiles, invite only profiles they created, and manage only
  permitted profiles.
- Regular account: view linked profiles and request eligible claims.
- Owning a CoachProfile does not automatically grant Coach authorization.

Inspect and reuse existing role and account-permission architecture.

Create reusable policy/service methods for:
- create?
- view?
- update?
- invite?
- review_claim?
- unlink?
- merge?
- archive?
- destroy?

Apply authorization to individual records and collection queries.

Prevent client-supplied account_id or created_by_account_id from bypassing
authorization.

Test IDOR, cross-organization access, denied overrides and administrative behavior.

STOP: Report the final permission matrix and passing tests.
```

### Phase 4 — Profile claims

**Status:** Implemented. See [`IDENTITY_228_PHASE_04_PROFILE_CLAIMS.md`](IDENTITY_228_PHASE_04_PROFILE_CLAIMS.md).

The Account dashboard allows claims of eligible, currently unclaimed profiles.

Adjust this proposed API contract to established conventions:

| Method | Endpoint | Purpose |
| --- | --- | --- |
| GET | /api/v1/profile_claim_candidates | Eligible profiles |
| POST | /api/v1/profile_claims | Submit claim |
| GET | /api/v1/profile_claims | Own claims |
| POST | /api/v1/profile_claims/:id/cancel | Cancel pending claim |

```text
# Phase 4 — Profile Claim Backend

Implement a secure polymorphic claim workflow for PlayerProfile and CoachProfile.

Suggested ProfileClaim fields:
- claimant_account_id
- claimable_type
- claimable_id
- status
- requested_at
- reviewed_by_account_id
- reviewed_at
- decision_reason
- verification_method
- timestamps

Statuses: pending, approved, rejected, cancelled.

## Discovery eligibility

An Account may discover unclaimed profiles only when:
- It has a verified eligible organization relationship; OR
- It has an established relationship with the same coach.

Inspect actual Organization, Group and Coach associations to implement this.

Do not equate "created by the same coach" with "currently coached by the same
coach" without an explicit business decision.

Enforce eligibility on the backend.

## Security

- Only authenticated Accounts may request claims.
- Never expose all unclaimed profiles globally.
- Limit returned personal data.
- Require identity verification before approval.
- Prevent duplicate pending claims from the same Account for the same profile.
- Permit competing legitimate claims to be reviewed safely.
- Record claim history permanently.
- Use appropriate indexes and pagination.

Test eligible/ineligible discovery, competing claims, cross-organization access,
cancellation and historical audit records.

STOP: Provide endpoint examples and test results.
```

### Phase 5 — Claim approval and linking

**Status:** Implemented. See [`IDENTITY_228_PHASE_05_CLAIM_APPROVAL.md`](IDENTITY_228_PHASE_05_CLAIM_APPROVAL.md).

Approval is an identity operation, not merely a status update.

```text
# Phase 5 — Claim Review and Account Linking

Implement review endpoints and a transactional approval service.

## Approval workflow

1. Authenticate the reviewing User.
2. Resolve their Account.
3. Authorize review within scope.
4. Lock the claim and target profile.
5. Verify the claim remains pending.
6. Verify identity evidence and eligibility.
7. Verify the profile is not linked to another Account.
8. Set profile.account_id to claimant_account_id.
9. Mark the claim approved.
10. Record reviewer, verification method and timestamps.
11. Resolve other pending claims for that profile with explicit audited outcomes.
12. Commit the transaction.
13. Send notifications after commit.

If the profile is already linked, return a conflict without changing ownership.

Do not automatically merge another PlayerProfile or CoachProfile belonging to
the claimant.

Use consistent error codes for forbidden, conflict, validation and missing records.

Support rejection with an optional internal reason and an appropriate public response.

Test simultaneous approvals and transaction rollback.

STOP: Show tests proving two Accounts cannot claim the same profile concurrently.
```

### Phase 6 — Invitations to existing or new Accounts

**Status:** Implemented. See [`IDENTITY_228_PHASE_06_PROFILE_INVITATIONS.md`](IDENTITY_228_PHASE_06_PROFILE_INVITATIONS.md). Phase 7 is next.

Support emails belonging to an existing User with an Account, and emails not yet belonging to a User.

```text
# Phase 6 — Profile Invitations

Implement invitations for both PlayerProfile and CoachProfile.

Suggested fields:
- invitable_type
- invitable_id
- invited_by_account_id
- invited_account_id (nullable)
- invited_email_normalized
- token_digest
- expires_at
- status
- accepted_at
- declined_at
- cancelled_at
- timestamps

Statuses: pending, accepted, declined, cancelled, expired.

## Rules

Admin and Curator may invite within authorized scope.

Coach may invite only profiles whose created_by_account_id matches their
Account, subject to scope restrictions.

## Existing User

1. Resolve the existing User/Account without exposing account existence to
   unauthorized callers.
2. Send a notification or invitation.
3. Require authentication as the intended recipient.
4. Recheck profile availability.
5. Link the profile to the existing Account transactionally.

## New User

1. Send an expiring invitation to the verified destination email.
2. Open the existing registration flow.
3. Verify email ownership through the invitation and required registration
   verification.
4. Create User and Account using the existing registration architecture.
5. Ensure the new Account has its required ContactDetails record.
6. Link the profile after authentication/verification.
7. Preserve original profile relationships and history.

Do not silently create an authenticated User when sending an invitation.

## Security

- Cryptographically secure, single-use tokens.
- Store only token digests.
- Rate-limit issuance and acceptance.
- Prevent cross-account acceptance.
- Prevent replay and expired-token acceptance.
- Lock profile rows during acceptance.
- Keep historical invitation records.
- Use the project's existing HTTP email provider integration.
- Never log raw invitation tokens.

Write request, model and concurrency tests.

STOP: Demonstrate existing-account and new-account invitation acceptance.
```

**Checkpoint 3:** Claims and invitations function at API level before frontend implementation begins.

### Phase 7 — Account dashboard

**Status: Implemented.** See [IDENTITY_228_PHASE_07_ACCOUNT_DASHBOARD.md](IDENTITY_228_PHASE_07_ACCOUNT_DASHBOARD.md) for the shipped scope, API behavior, security decisions, and verification status.

The Account dashboard is the central location for linked profiles, pending claims and invitations.

Conceptual layout:

| Section | Content |
| --- | --- |
| My profiles | Linked player and coach profiles with contextual labels |
| Find and claim a profile | Search eligible unclaimed profiles within permitted relationships |
| My pending claims | Current status and available cancellation action |
| Invitations received | Acceptance and decline actions |
| History | Previous claim and invitation outcomes |

```text
# Phase 7 — Account Profile Dashboard

Implement the React/TypeScript account profile dashboard.

## Sections

1. My PlayerProfiles
2. My CoachProfiles
3. Find and claim a profile
4. My pending claims
5. Invitations received
6. Claim and invitation history

## Search

Provide:
- Player/Coach selector
- Name search
- Eligible organization filter where appropriate
- Paginated results
- Claim request action
- Pending/approved/rejected states

Show only backend-authorized candidates.

## UX

- Loading, empty and error states
- Confirmation before submitting a claim
- Explain that approval is required
- Clear handling of already-linked profiles
- Responsive mobile layout
- Accessible controls
- No public disclosure of sensitive contact data

Use existing components, API clients, authentication context and routing conventions.

Do not introduce a second source of authentication state.

Add component and end-to-end tests.

STOP: Demonstrate the claim journey from search through status display.
```

### Phase 8 — Admin, Curator and Coach dashboard

**Status: Implemented.** See [IDENTITY_228_PHASE_08_PROFILE_MANAGEMENT.md](IDENTITY_228_PHASE_08_PROFILE_MANAGEMENT.md) for the role boundary, endpoints, UX, and verification.

```text
# Phase 8 — Profile Management Dashboard

Implement a management interface for Admin, Curator and Coach Accounts.

## Views

- Pending profile claims
- Pending invitations
- Claim history
- Invitation history
- Linked and unclaimed profiles within authorized scope

## Actions

- Inspect claim
- Review verification evidence
- Approve or reject
- Invite existing Account or email
- Resend eligible invitation
- Cancel invitation
- View audit history

## Scope

Admin: authorized administrative scope.
Curator: authorized organization scope.
Coach: profiles created by that Coach Account for invitation operations;
other review capabilities only when explicitly granted by policy.

Do not grant claim approval merely because someone created a profile unless
the approved authorization rules permit it.

Use server-side filtering and record-level authorization.

## UX

Separate tabs for Claims and Invitations, with profile-type and status filters.

Display useful context without unnecessarily exposing private contact data.

Add React tests for permission-gated actions and backend integration tests
for authorization.

STOP: Demonstrate behavior for each role.
```

### Phase 9 — Remove People workflows

Retire Person only when no production path depends on it. Destructive schema cleanup remains a separate rollout step.

```text
# Phase 9 — Remove Person and People Workflows

Use the verified migration and dependency audit.

## Frontend

Remove:
- /people page and navigation
- Person creation UI
- Person claim UI
- Person invitation UI
- Person consolidation UI

Replace necessary account/profile functionality with the new workflows.

## Backend

Find all references to:
- Person
- person_id
- PeopleController
- Person claims/invitations
- Person serializers and services

Migrate or replace every legitimate dependency.

## Required verification

- No active model or API depends on Person.
- No historical foreign key is orphaned.
- Existing authentication works.
- Existing training and assessment APIs work.
- Existing organization and group membership works.
- Frontend routes no longer link to /people.
- Old API clients receive intentional compatibility responses during rollout.

Do not drop Person tables or columns in this phase unless production cutover
and contract-migration approval have explicitly been given.

Document the eventual removal migration separately.

STOP: Produce a dependency-free verification report.
```

### Phase 10 — Profile merging, archiving and deletion

This is separate from claims. An Account may legitimately own multiple profiles without merging them. An optional explicit merge, such as PlayerProfile #82 into #14, must preserve traceable historical records.

```text
# Phase 10 — Merge, Archive and Delete Profiles

Implement explicit duplicate-profile management.

## Requirements

1. Never merge automatically during a claim or invitation.
2. Support only same-type profile merges initially.
3. Require authorization and explicit confirmation.
4. Validate organizational and historical constraints.
5. Preserve assessment, tournament, training and ranking history.
6. Preserve source profile identity in an auditable merge record.
7. Prevent circular merges and merging into archived or invalid targets.
8. Use a transaction and lock relevant records.
9. Prefer archive/redirect semantics when historical references exist.
10. Never blindly update every foreign key to the target profile.

## Hard deletion

Permit hard deletion only when a complete dependency check proves no
protected references exist.

Inspect direct and indirect associations, including:
- Group memberships
- Training sessions
- Assessment sessions and results
- Rankings
- Tournaments
- Schedules
- Invitations and claims
- Audit records
- Other existing domain relationships

If deletion is unsafe, explain why and offer archive instead.

Avoid dependent: :destroy on historically important associations.

Test merges, archived records, forbidden deletes, race conditions and retained history.

STOP: Produce a deletion dependency matrix.
```

### Phase 11 — Security, testing and regression audit

```text
# Phase 11 — Full Regression and Security Audit

Run a complete backend/frontend audit.

## Identity

- User login/logout
- Account resolution
- Registration
- Password recovery
- Existing roles and permission checks
- Accounts with no profiles
- Accounts with many profiles
- Unclaimed profiles

## Claims

- Eligibility
- Scope restrictions
- Duplicate requests
- Identity verification
- Approval/rejection
- Competing claims
- Concurrent approvals
- Audit history

## Invitations

- Existing User acceptance
- New User registration
- Expired tokens
- Replayed tokens
- Wrong-account acceptance
- Cancelled invitations
- Concurrent acceptance
- Email delivery failures

## Historical integrity

Verify existing Training, Tournaments, Assessments, Rankings, Organizations,
Groups and Schedules continue working and retain their references.

## Security

Test:
- IDOR
- Mass assignment
- Privilege escalation
- Tenant/scope bypass
- Role overrides
- Token leakage
- Account enumeration
- Sensitive-data exposure
- Rate limiting

Run available Rails tests, RuboCop, TypeScript checks, ESLint, build and
Playwright tests.

Report:
- Commands run
- Passed tests
- Failed tests
- Untested areas
- Outstanding risks
- Required fixes

Do not deploy automatically.
```

### Phase 12 — Production rollout and cleanup

The API and frontend deploy independently. Preserve compatibility across deployment boundaries.

```text
# Phase 12 — Safe Production Rollout

Prepare a deployment plan for the independently hosted Rails API and React frontend.

## Before deployment

1. Back up PostgreSQL.
2. Test restoring the backup.
3. Capture baseline row counts and relationship checks.
4. Verify idempotent data migration on staging.
5. Confirm new code supports the transitional schema.
6. Confirm the previous production version can run during the expand phase.
7. Identify long-running migrations and lock risks.

## Deployment

1. Deploy additive schema migrations.
2. Run validated backfills.
3. Enable dual-read/write or controlled compatibility logic only where needed.
4. Deploy API changes.
5. Deploy frontend changes.
6. Validate authentication and Account resolution.
7. Smoke-test claims and invitations.
8. Check training, assessment and tournament functionality.
9. Monitor errors and database health.

## Final cleanup

Only after a stable observation period:
- Remove unused Person code.
- Remove unused Person foreign keys.
- Drop obsolete Person tables in a separately approved contract migration.
- Remove temporary compatibility code.
- Update API documentation and entity diagrams.

## Rollback

Document rollback separately for:
- Frontend release
- API release
- Additive schema changes
- Data backfill
- Final destructive schema cleanup

Do not assume database rollback reverses deleted or transformed identity data.

Provide a release checklist and an explicit go/no-go decision.

STOP: Do not deploy or execute destructive migrations without approval.
```

## 7. Important edge cases

| Scenario | Expected behavior |
| --- | --- |
| Coach creates player without registration | Profile exists with account_id = NULL |
| Same coach creates two profiles for one human | Profiles remain independent until reviewed |
| Existing User claims one profile | Links to their Account after approval |
| User claims a second profile | Both link to the same Account |
| Account has player and coach profiles | Both work independently |
| Invitation targets existing User | No duplicate User/Account created |
| Invitation targets new email | Registration creates User/Account before linking |
| Two Accounts request same profile | Competing claims reviewed; only one succeeds |
| Claim approval races invitation acceptance | Transactional conflict handling prevents double assignment |
| Coach invites another coach's created profile | Forbidden unless separately authorized |
| User searches outside eligible relationships | No unauthorized profile data returned |
| Profile has assessment history | Hard deletion blocked |
| Account owns multiple profiles | No automatic merge |
| Account email changes | Linked profiles remain linked |
| Existing creator cannot be identified | Document legacy exception; do not fabricate ownership |

## 8. Suggested code organization

These are proposed locations, not assertions about existing files. Follow conventions identified in Phase 1, including existing Player/Coach model names.

```text
beachvolleyballproject_api/
├── app/
│   ├── models/
│   │   ├── user.rb
│   │   ├── account.rb
│   │   ├── contact_detail.rb
│   │   ├── player_profile.rb
│   │   ├── coach_profile.rb
│   │   ├── profile_claim.rb
│   │   └── profile_invitation.rb
│   ├── services/
│   │   └── profiles/
│   │       ├── claim_service.rb
│   │       ├── claim_review_service.rb
│   │       ├── invitation_service.rb
│   │       ├── invitation_acceptance_service.rb
│   │       ├── merge_service.rb
│   │       └── deletion_guard.rb
│   ├── policies/
│   │   └── ...
│   └── controllers/api/v1/
│       ├── profile_claims_controller.rb
│       └── profile_invitations_controller.rb
└── docs/
    └── account_identity_refactor_audit.md
```

```text
beachvolleyballproject_frontend/
└── src/
    ├── features/
    │   ├── account/
    │   │   ├── components/
    │   │   ├── pages/
    │   │   └── services/
    │   ├── profile-claims/
    │   │   ├── components/
    │   │   ├── pages/
    │   │   └── services/
    │   └── profile-invitations/
    │       ├── components/
    │       ├── pages/
    │       └── services/
    └── ...
```

Avoid creating a generic polymorphic Profile parent table unless the audit uncovers a genuine need. Polymorphic claim/invitation associations can share workflow logic without combining the two profile domains.

## 9. Final architecture acceptance criteria

The supplied conversation's acceptance-criteria block contained only a placeholder. This checklist makes the requirements elsewhere in the plan explicit.

- [ ] Actual User → Account cardinality and foreign-key direction audited and preserved.
- [ ] Existing login, registration, sessions and password recovery pass regression checks.
- [ ] Account remains the application authorization principal.
- [ ] Accounts support zero or multiple PlayerProfiles and CoachProfiles.
- [ ] Unclaimed profiles exist without an Account.
- [ ] Creator attribution remains separate from linked ownership.
- [ ] Private contact information has a defined source of truth and access policy.
- [ ] Backfill is idempotent; ambiguous mappings are identified rather than guessed.
- [ ] Historical domain references and row counts are verified.
- [ ] Collection and record-level permissions are enforced on the backend.
- [ ] Claims require eligibility and identity verification.
- [ ] Invitations support existing and new Users without duplicating Accounts.
- [ ] Approval and acceptance cannot assign one profile to two Accounts concurrently.
- [ ] Tokens expire, resist replay and are stored as digests.
- [ ] Claiming and invitation acceptance never automatically merge or delete profiles.
- [ ] Merge/archive/delete operations preserve protected history and audit records.
- [ ] Account and management dashboards handle permission, loading and error states.
- [ ] Person dependencies have been migrated before destructive cleanup.
- [ ] API/frontend compatibility, rollout and rollback are documented.
- [ ] Actual test commands, results and untested areas are reported.
- [ ] Production deployment and destructive cleanup receive the required approval.

## 10. Recommended implementation order

Start with **Phase 1 only**. Its output should settle the actual User → Account relationship, every existing Person dependency, and whether the models are named Player/Coach or PlayerProfile/CoachProfile.

Complete the additive schema migration and backend authorization before frontend dashboards. Leave destructive removal of Person until the final deployment stage. This yields the simpler Account-centric identity model while protecting existing application behavior and volleyball history.
