# Person / Player / Coach Identity Model (Phase 1)

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

## Person statuses

- `active` — normal record
- `archived` — no longer active, history kept
- `merged` — duplicate resolved into another Person; `merged_into_id` points
  at the canonical record. Merged people are excluded from `Person.canonical`
  and resolved via `Person#canonical_person`. Records are never hard-deleted.

## Not yet implemented (future phases)

- Training session participants referencing `player_profile`
- Assessments referencing `player_profile` + `coach_profile` (coach-authoritative)
- `PlayerCoach` join model, groups
- `PersonClaim` / invitations (invited person claims their existing Person)
- `PersonMerge` consolidation service
- Tournament participation, `assertion_source` / dispute states
