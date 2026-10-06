# Issue 228 — Phase 9: Retire People workflows

## Status

**User-facing Person creation, editing, duplicate lookup, invitation, and consolidation flows have been removed from the active profile UI. Phase 9 is not complete:** the required dependency-free backend cutover cannot be claimed while Account, organisation/group membership, claim compatibility, and historical domain records still depend on `Person` / `person_id`.

No Person tables or columns were dropped. Phase 12 remains the planned contract migration and requires a separately approved production cutover.

## Changes in this phase

- Player and Coach creation now records profile display name and volleyball attributes only. The UI no longer searches for People, creates People, records contact details, links a profile to a Person, or suggests Person duplicates.
- Player and Coach edit pages update profile-owned fields only. Legacy Person/contact data and Account data are not edited through these forms.
- Player and Coach detail/catalogue surfaces no longer show legacy Person email, phone, date of birth, or creation-source fields. Account linking is described in account/profile language.
- Identity no longer displays a Person ID or redeems legacy Person-to-Account invitation tokens; the active redemption path is profile claim invitations.
- Coach profile creation and update now accept `display_name`, matching the existing nullable/personless CoachProfile schema.
- Profile names resolve from `display_name` first and fall back to the legacy Person name. Existing Person-backed records remain readable while migrated.
- The Identity page no longer exposes Person consolidation.
- Profile invitation history no longer offers a People filter or displays legacy Person invitation rows. The supported flow is profile claims and profile invitations.
- There is no active `/people` page or navigation entry. Existing profile edit URLs remain `/players/:id/edit` and `/coaches/:id/edit`.

## Dependency audit

The frontend no longer offers Person creation, Person editing, Person duplicate lookup, or Person consolidation as a profile-management workflow. The `GET /api/v1/people` compatibility endpoint remains because organisation roster management still searches for Person-backed membership subjects.

The backend is **not** dependency-free. Confirmed active dependencies include:

- `Account belongs_to :person`; the account/contact migration and backfill still use `Person` as an intermediate identity link.
- `OrganisationMembership` and `GroupMembership` are keyed by Person. Organisation and group roster operations, group participants, and training participant resolution consume `person_id`.
- PlayerProfile and CoachProfile retain optional `person_id` for existing records, profile visibility within organisation peers, legacy serializers, and old claim/invitation compatibility.
- Training, assessments, account signup/contact synchronization, person claim compatibility, and deletion guards contain Person-backed reads or foreign keys.
- Historical Person foreign keys and records remain in the database and are not orphaned by this phase because no rows were deleted or repointed.

Removing these dependencies in this phase would require replacing durable organisation/group membership identity and converting the account/contact link, with compatibility behavior for existing roster and training history. The documented migration order places production observation and contract cleanup later. Therefore the Phase 9 prompt's requirement “No active model or API depends on Person” is **not met** and Phase 9 remains incomplete pending the active-data/API cutover. This is a recorded dependency, not a claim that the Person model is retired.

## Verification checklist

- [x] Profile create/edit UI no longer creates or changes Person/contact data.
- [x] Person consolidation UI removed from Identity.
- [x] Person invitation subjects removed from the active management history UI.
- [x] No People route or navigation item is present.
- [ ] No active model/API depends on Person — blocked by Account, organisation/group roster, and training compatibility described above.
- [ ] Dependency-free production verification report — pending completion of those migrations.
- [ ] Existing authentication, training, assessment, organisation, and group workflows verified after the full cutover — not claimed in this phase.
- [x] Person tables/columns retained for the later approved contract migration.

Focused verification for the implemented slice:

- Frontend API, profile, Identity, management-dashboard, and detail-page suites: **115 tests passed**.
- Frontend production build (`npm run build`): passed. Vite reports the existing large-chunk warning.
- Rails player/coach controller and model suites: **105 tests, 355 assertions, 0 failures/errors**.
- `git diff --check`: passed in both repositories.

## Files changed

- Frontend profile create/edit forms, profile details, catalogues, Identity, and profile-management UI.
- `CoachesController` permits profile display names; `PlayerProfile#full_name` and `CoachProfile#full_name` prefer profile display names and retain Person fallback.
- Frontend API input types permit coach display names.

## Next action

Before Phase 10, resolve the data ownership cutover for account/contact, organisation/group memberships, and existing history references. Do not drop `people`, `person_id`, or compatibility endpoints as part of this partial phase.
