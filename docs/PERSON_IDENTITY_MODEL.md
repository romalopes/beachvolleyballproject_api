# Person / Player / Coach Identity Model

Phases 1–3 are implemented (identity model, training participants, player/coach
API + SPA).

## Core principle

> A real-world person can exist in the Beach Volleyball Project independently
> of whether they have an account. An Account is attached to that Person when
> authentication becomes available.

## Structure

```text
User (authentication: email + password)
  └── Account (bridge, 1—1)
        └── Person (domain identity)
              ├── 0..1 Account
              ├── 0..1 PlayerProfile (position, level, status)
              ├── 0..1 CoachProfile (coaching_level, qualifications)
              └── PersonAlias (nicknames, alternate spellings)
```

Invariants (enforced by unique indexes + model validations):

- `accounts.person_id` unique — one Account per Person max
- `player_profiles.person_id` unique — one PlayerProfile per Person max
- `coach_profiles.person_id` unique — one CoachProfile per Person max
- Every Account always has a Person (`Account#ensure_person` runs on create).
  Authentication is optional; domain identity is mandatory.

## What changed

- `people`, `player_profiles`, `coach_profiles`, `person_aliases` tables added.
- `first_name`, `last_name`, `phone`, `date_of_birth` moved from `accounts` to
  `people`. Existing accounts were backfilled (one Person per Account, contact
  email taken from the User, `creation_source: "signup"`).
- `Account` delegates the old contact fields to `Person` and captures values
  assigned before the Person exists (transitional setters), so the web form
  and the JSON API (`/api/v1/account`) keep their previous contract:
  reads come from the Person, writes go to the Person.
- `User has_one :person, through: :account`.

## Creating people without accounts

A coach (or admin) can create `Person + PlayerProfile` with no Account:

```ruby
person = Person.create!(first_name: "Pedro", last_name: "Santos",
                        creation_source: "coach_created", created_by: coach_user)
person.create_player_profile!(preferred_position: "setter", level: "beginner")
```

Such a person is immediately usable for training sessions, attendance,
assessments, media and (later) tournaments — those features reference the
Person/profile, never the User.

## Single creation path for staff-recorded people

`PersonCreationService` is the one place that stamps provenance for people
entered by staff (`creation_source: "coach_created"`, `created_by`, `status:
"active"`). Used by:

- `Api::V1::PlayersController#create` / `Api::V1::CoachesController#create`
  (nested `person` attributes);
- `Api::V1::TrainingSessionsController#resolve_inline_participants!` (a coach
  adding a participant who has no profile yet).

Client-supplied `created_by_id` is never trusted: the author always comes from
the authenticated request.

## Avoiding duplicate people

`PersonDuplicateFinder` suggests people that may already describe the same human
(email exact, or first + last name match, case-insensitive; merged people
excluded). It is *suggestion only* — nothing is ever merged automatically,
because a name is not identity evidence.

- `GET /api/v1/people?q=` — the lookup a coach runs before recording someone
  (staff only: it returns contact details). Bounded to 25 rows.
- `POST /api/v1/players|coaches` answers with `possible_duplicates` built from
  the same `Person#identity_summary` payload, so the SPA renders search results
  and duplicate warnings with one component.
- Creating a profile either names an existing person (`person_id`) or records a
  new one (`person` attributes). Linking never rewrites the person's provenance.

## Person statuses

- `active` — normal record
- `archived` — no longer active, history kept
- `merged` — duplicate resolved into another Person; `merged_into_id` points
  at the canonical record. Merged people are excluded from `Person.canonical`
  and resolved via `Person#canonical_person`. Records are never hard-deleted.

## Training session participants (Phase 2)

`training_session_participants` joins a session to a `player_profile` (never a
User): a participant is whoever is expected, whether or not they can sign in.

- `status` — `invited → confirmed → attended | absent`, with `declined` as the
  opt-out. Attendance is the same row, so the invitation and its outcome cannot
  disagree.
- `visibility` on the session — `shared` (normal schedule) or `private` (only
  coaches/curators/admins). `TrainingSession.visible_to(user)` applies it.
- `GET /api/v1/training_sessions?mine=1` — the signed-in person's own sessions
  (`participated_by` their player profile) for the "My schedule" view.
- A participant row may carry inline `person` attributes instead of a
  `player_profile_id`: the server then creates Person + PlayerProfile
  (`coach_created`, no Account) so a coach can schedule someone on the spot.

## People, players and coaches API (Phase 3)

| Endpoint | Who | Notes |
| --- | --- | --- |
| `GET /api/v1/people?q=&email=` | coach, curator, admin | identity search, 25 rows max (flat array) |
| `GET /api/v1/players?q=&email=&status=&page=&per_page=` | coach, curator, admin | paginated (`{ data, meta }`), 20 per page |
| `GET /api/v1/players/:id` | coach, curator, admin | adds `training_session_count` and the training history |
| `POST /api/v1/players` | coach, admin | `person_id` or nested `person`; `player_profile`; returns `possible_duplicates` |
| `PATCH /api/v1/players/:id` | coach, admin | edits `player_profile` + nested `person` (contact details); `person_id` refused with 422 |
| `GET /api/v1/coaches?q=&email=&status=&page=&per_page=` | coach, curator, admin | paginated, same shape as players |
| `GET /api/v1/coaches/:id` | coach, curator, admin | |
| `POST /api/v1/coaches` | coach, admin | same shape as players; a CoachProfile grants no permissions |
| `PATCH /api/v1/coaches/:id` | coach, admin | same as the player edit |

The two catalogues answer with the shared envelope
(`{ data: [...], meta: { page, per_page, total, total_pages } }`, see
`Pagination`); `per_page` defaults to 20 and is clamped to 1..100, so the client
can size a page but never dump the table. The training form's player picker asks
for `per_page=100` because it filters the roster locally while a coach types —
if a club ever exceeds 100 players, that picker should move to server-side search.

Reads are limited to training managers because the payloads carry contact
details. The SPA mirrors that: `/players`, `/players/:id` and `/coaches` sit
behind `ManagerRoute`, and the "New player"/"New coach" buttons only render for
coaches and admins. Lowercase statuses (`"connected"`, `"profile_only"`) are the
wire format.

## Editing profiles and renames

A correction is normal club work ("it was Maria, not Ana"), so profiles are
editable — but an edit can never turn into an identity change:

- `PATCH /players/:id` updates the PlayerProfile **and** the person's contact
  details. Sending a different `person_id` returns 422: re-pointing a profile is
  a merge, not an edit.
- Nested person attributes use
  `accepts_nested_attributes_for :person, update_only: true`. Without it Rails
  *replaces* the person on a `has_one` whenever the nested hash carries no id,
  which would silently create a second identity on every contact-detail change.
- Provenance (`creation_source`, `created_by_id`) is never rewritten by an edit.
- A blank contact field means "no value" and is stored as NULL, so a wrong phone
  number or email can actually be cleared.
- **Renames keep the previous name.** `Person` records it as a `PersonAlias`
  (`alias_type: "previous_name"`) from an `after_update` hook, because a person
  can be renamed through the profile API *and* through their own account page.
  `GET /api/v1/people` matches aliases as well as names, so a coach still finds
  "Peter Smith" after the rename to "Pedro Silva"; the payload carries `aliases`
  and the SPA shows "also known as …".
- Saving answers with `possible_duplicates` again — a correction is when a
  duplicate usually surfaces. Nothing is merged automatically.
- Only one thing is missing on purpose: **there is no delete.** `status` can be
  set to `archived` through the same PATCH; hard deletion stays unimplemented
  because `PlayerProfile has_many :training_session_participants, dependent:
  :destroy` would take the attendance history with it.

## Removing a profile: archiving, never deleting

Archiving is the only removal path, and it is a flag:

- `PATCH /players/:id` (or `/coaches/:id`) with
  `player_profile: { status: "archived" }` retires the profile; `"active"`
  restores it. There is **no `destroy` route** — `DELETE /api/v1/players/:id`
  returns 404, pinned by a test, because the model's `dependent: :destroy` chain
  would let a single call wipe every attendance row that referenced the player.
- Nothing cascades: the Person, the profile, its roster rows and their statuses
  all stay. Archiving therefore never loses history, and it is reversible.
- The catalogues list **active** profiles by default; `?status=archived` lists
  the retired ones (an explicit filter *replaces* the active default — ANDing the
  two could only ever return nothing, which is what the old code did). An
  unknown status is rejected with 422 rather than silently returning [].
- Because the picker only ever asks for active players, an archived player
  cannot be added to a *new* training session, while every past session keeps
  their name, status and notes.
- The SPA offers this as an explicit mode ("Show archived") with an "Archived"
  tag plus Archive/Restore actions — archiving asks for confirmation and says
  what it does ("training history is kept"), restoring is one click.

## Not yet implemented (future phases)

- Assessments referencing `player_profile` + `coach_profile` (coach-authoritative)
- `PlayerCoach` join model, groups
- `PersonClaim` / invitations (invited person claims their existing Person)
- `PersonMerge` consolidation service
- Tournament participation, `assertion_source` / dispute states
