# Assessment Integration Plan (Phase 4)

How coach assessments of players are modelled, scored, published and exposed.

This is the contract for Phase 4: the rating scale, the data model, the API and
the SPA surface, plus the rules that are easy to get subtly wrong (who may see a
row, who may change it, and what "never deleted" means here).

Sub-phases:

| Sub-phase | Deliverable |
| --- | --- |
| 4.1 | `assessments` table, `RatingScale`, `Assessment` model, fixtures, model/service tests |
| 4.2 | `/api/v1/assessments` endpoints, payload additions, `me` payload additions |
| 4.3 | SPA: rating utilities, score badge, list, form, player/coach/session sections |
| 4.4 | This document finalised, roadmap pointer, assumptions, full verification gate |

## Why this phase

The identity model already records *who exists* (Person + PlayerProfile /
CoachProfile) and the skill/drill stream already records *what is worked on*
(Skill, Category, TrainingFocus). Assessments are the missing join between the
two: what a coach observed a player do, against a skill.

`Person`'s own documentation anticipated it — *"volleyball records — training
participation, assessments, tournament results — always reference a Person
(through its profiles)"* — which is why an assessment names a **PlayerProfile**
(who was assessed) and a **CoachProfile** (who assessed), never a `User`.

Assessments are **coach-authoritative**: the number is the coach's professional
opinion, so it is attributed to a coach, editable by that coach, and never
silently rewritten by anyone else.

## Decision log

Every decision below is ratified; the alternatives are recorded so a later
reader can see what was weighed.

| # | Decision |
| --- | --- |
| D1 | The canonical rating is an integer **0–100**, one per assessment, per skill |
| D2 | The coach states the scale used: **1–5** or **1–10**; the scale is stored on the row |
| D3 | Canonical → **0–10** display = `floor(score / 10)` |
| D4 | Canonical → **1–5** display = `min(5, floor(score / 20) + 1)` — equal-width 20-point bands |
| D5 | Entry → canonical: **1–10** = `n × 10`; **1–5** = the band midpoint `{1→10, 2→30, 3→50, 4→70, 5→90}` |
| D6 | `reported_value` + `scale` are stored next to `score`; requests carry only `value` + `scale`, the server derives `score` |
| D7 | `coach_profile_id` is **NOT NULL**: an assessment always names a domain coach |
| D8 | The assessor is resolved server-side: the request may name one; otherwise it is the caller's own coach profile; if the caller has none the request is refused with **422** — a profile is never minted silently |
| D9 | Only oversight (curator/admin) may attribute an assessment to another coach; a coach may only attribute to their own profile (**403** otherwise) |
| D10 | **No self-assessment**: the assessed player and the assessing coach must be different people (**422**) |
| D11 | The rubric is a `Skill` **XOR** free-text `custom_skill`, mirroring `training_focuses` |
| D12 | Statuses are `draft`, `active`, `withdrawn`; new rows default to **`draft`** (mirrors training sessions) |
| D13 | There is **no state machine**: any status change is an ordinary PATCH by someone with authority; the only extra rule is "publishing requires a score" |
| D14 | **Existence** = a single rule: a row exists for you if it is `active` **and** the player exists for you, **or** you are a stakeholder (recorder or attributed coach — in any status), **or** you are oversight |
| D15 | There is **no `include_private`** on assessments: no query parameter widens visibility |
| D16 | **Authority** = recorder ∪ attributed coach ∪ oversight (`manageable_by?`), with `require_content_creator!` for creation |
| D17 | `withdrawn` joins `draft` in the non-public bucket: visible to stakeholders and oversight, tagged in history, never in aggregates |
| D18 | Nothing is hard-deleted: there is **no `DELETE` route** (404), and profiles use `dependent: :restrict_with_error` |
| D19 | Aggregates (`assessment_count`, latest-per-skill) count **`active` rows only** |
| D20 | `PUBLICLY_VISIBLE_STATUSES = %w[active]` — a deliberate divergence from `TrainingSession`, where `cancelled` remains public; recorded here so it is not "fixed" back |
| D21 | A draft may exist **unrated** (the assignment workflow): `score`/`reported_value` are nullable, constrained by status |
| D22 | Any `coach_profile` may be attributed, including one whose Person has no account; the picker flags those, and the recorder plus oversight manage them |
| D23 | `player_profiles.level` stays a free-text coach summary and is **never** written by an assessment |
| D24 | **Oversight is the curator/admin pair, deliberately not `User#content_manager?`.** For the shared schedule a coach counts as a manager (a session created yesterday must stay manageable by the other coaches), but a rating is one named coach's claim about a player: a coach reaches only their own rows, and curators/admins oversee all (the same pair `PlayerProfile#visible_to_user?` treats as unlimited) |
| D25 | Referential integrity: `training_session_id` is `ON DELETE :nullify` (the rating outlives the schedule entry), while `skill_id` is left restrictive — the XOR constraint requires a rubric, so an **in-use skill cannot be hard-deleted** |

## The rating scale

A coach thinks in the scale they know ("4 out of 5", "7 out of 10"). The system
needs one comparable number, so it stores a canonical **0–100** score and keeps
the coach's own input next to it.

What is stored on every assessment:

| Column | Meaning |
| --- | --- |
| `score` | canonical 0–100 — the only value used for comparison, sorting, averages |
| `reported_value` | what the coach actually typed (1…5 or 1…10) |
| `scale` | which scale they used: `one_to_five` or `one_to_ten` |

Keeping the typed value is what makes the scale **revisable**: if the bands are
ever re-tuned, `score` is recomputed from `reported_value` + `scale` in a data
migration instead of being lost. `score` is derived data; `reported_value` is the
record of intent.

### Entry: what the coach typed → canonical

| Coach types | Canonical `score` | Rule |
| --- | --- | --- |
| `n` on **1–10** (1…10) | `n × 10` → 10, 20, …, 100 | `n * 10` |
| `n` on **1–5** (1…5) | `{1→10, 2→30, 3→50, 4→70, 5→90}` | midpoint of the band in D4 |

Band midpoints are the neutral choice: unbiased, symmetric, and exactly
invertible — `4/5` stores `70`, which displays back as `4/5` **and** `7/10`.
The alternatives (band starts `0/20/40/60/80`, or top edges `19/39/59/79/100`)
are a one-line change to a single constant, `RatingScale::ENTRY_VALUES`.

### Display: canonical → both scales

| Display | Bands | Formula |
| --- | --- | --- |
| 0–10 | `0..9→0`, `10..19→1`, …, `90..99→9`, `100→10` | `score / 10` (floor) |
| 1–5 | `0..19→1`, `20..39→2`, `40..59→3`, `60..79→4`, `80..100→5` | `min(5, score / 20 + 1)` |

### Acceptance matrix (asserted in both repositories)

```
score  0  9 10 19 20 29 30 39 40 49 50 59 60 69 70 79 80 89 90 99 100
0–10   0  0  1  1  2  2  3  3  4  4  5  5  6  6  7  7  8  8  9  9  10
1–5    1  1  1  1  2  2  2  2  3  3  3  3  4  4  4  4  5  5  5  5   5
```

Properties asserted alongside it:

- **Round-trip, 1–10**: `to_ten(to_score(n, scale: "one_to_ten")) == n`
- **Round-trip, 1–5**: `to_five(to_score(n, scale: "one_to_five")) == n`
- **Cross-scale agreement**: `70` is at once `7/10` and `4/5`; `10` is `1/10` and `1/5`; `90` is `9/10` and `5/5`
- **Monotonicity**: both display functions are non-decreasing over `0..100`
- **Rejection, not clamping**: an out-of-range or non-numeric value raises (model validation → 422); unlike pagination, a score is never silently truncated

### One implementation, two languages

- `app/services/rating_scale.rb` — authoritative. `SCALES`, `ENTRY_VALUES`,
  `to_score`, `legal_value?`, `to_ten`, `to_five`, `describe`.
- `src/utils/rating.ts` — mirror, for the live preview and for rendering badges
  only. **The server always converts**: a client cannot store a canonical score
  of its own choosing, which is why the API takes `value` + `scale`.
- Both are covered by the same matrix above.

## Domain model (4.1)

```text
Assessment
  ├── player_profile   (0..1 per row, NOT NULL)  — who was assessed
  ├── coach_profile    (0..1 per row, NOT NULL)  — who assessed  (D7)
  ├── created_by       (User, nullable)          — provenance, stamped from the request
  ├── skill            (nullable)  XOR  custom_skill (nullable)  — what was assessed (D11)
  └── training_session (nullable)                — the session it was observed in
        score           integer 0..100, nullable only while draft (D21)
        reported_value  integer (1..5 or 1..10 per scale)
        scale           one_to_five | one_to_ten
        status          draft | active | withdrawn (D12)
        notes           free text
```

Shape notes:

- **Ownership lives on the profile, not the Person** (the same reasoning as the
  visibility work in Phase 3.C): one Person can carry a player profile and a
  coach profile recorded by different staff, so the assessor and the assessed are
  named by profile.
- `created_by` is kept **beside** `coach_profile_id` because the two can diverge
  exactly when the oversight flow is used (a curator records on behalf of a coach)
  and because authority is partly keyed on the recorder.
- Indexes: `[player_profile_id, created_at]` (history per player), `status`
  (catalogue filters). Foreign keys on all five references — with one exception:
  `training_session_id` is `ON DELETE :nullify` so deleting a session neither
  destroys the ratings recorded in it nor is blocked by them (D25).
- Check constraints: `assessments_status`, `assessments_score_range`,
  `assessments_score_pair` (score and reported_value are both set or both NULL),
  `assessments_published_requires_score`, `assessments_skill_xor_custom_skill`.
  The self-assessment rule cannot be a constraint (it compares across tables) and
  therefore lives as a model validation.

### Lifecycle

```
draft ──publish──▶ active ──retract──▶ withdrawn
  ▲                                        │
  └────────────── reinstate ◀──────────────┘
```

There is **no state machine** (D13): every arrow is an ordinary `PATCH` by
someone with authority, so the flow stays as simple as the training-session
status it mirrors. The one integrity rule is that publishing requires a score —
an unrated row may only be a draft, or it would read as an evaluation of the
player without containing one.

### Existence: who may see a row (D14–D15)

> A row exists for you if **(a)** it is `active` and the assessed player exists
> for you, **or (b)** you are a stakeholder — its recorder or its attributed
> coach, in any status — **or (c)** you are oversight (curator/admin, by role).

| Viewer | active / visible player | active / player private elsewhere | own or attributed (draft/withdrawn) | someone else's draft/withdrawn |
| --- | --- | --- | --- | --- |
| curator / admin | yes | yes | yes | yes |
| recorder | yes | yes | yes | no |
| attributed coach | yes | yes | yes | no |
| other coach | yes | no — 404 | no | no — 404 |
| player / guest | no | no | no | no |

Two things this table is doing deliberately:

- **Clause (b) beats the player's visibility.** A curator can attribute an
  assessment on a player who is private to another coach; without that clause the
  attributed coach would lose sight of their own record.
- **A row that does not exist for you answers 404, not 403** — the same rule the
  player endpoints use, so nothing leaks about whether a private player exists.

Visibility is **not authorization** and is never widened by a query parameter:
this API has no `include_private` (D15). A client cannot ask to see more; only a
role, an ownership relationship or the row's own status change what exists.

### Authority: who may change a row (D9, D16)

| Action | coach (own profile) | recorder | attributed coach | curator / admin |
| --- | --- | --- | --- | --- |
| create, attributed to self | yes | – | – | yes |
| create, attributed to another coach | **403** | – | – | yes |
| edit, publish, retract, reinstate | yes | yes | yes | yes |
| delete | no route (404) | no route (404) | no route (404) | no route (404) |

`manageable_by?(user)` is the single source of truth for the middle row, so
controllers never re-implement it. The self-assessment rule (D10) applies to
every actor: a person who holds both profiles can never be the assessor of their
own player profile.

## API (4.2)

`resources :assessments, only: %i[index show create update]` — there is no
`destroy` route, so `DELETE /api/v1/assessments/:id` is a 404 pinned by a test
(D18), exactly as for players and coaches.

| Endpoint | Who | Contract |
| --- | --- | --- |
| `GET /api/v1/assessments?player_id=&coach_id=&skill_id=&training_session_id=&status=&mine=&page=&per_page=` | training manager | always scoped by `visible_to(Current.user)`; `status` defaults to `active` and an explicit value replaces that default; `mine` narrows to rows you recorded or are attributed in; **no `include_private`** |
| `GET /api/v1/assessments/:id` | training manager | 404 unless the row exists for the caller |
| `POST /api/v1/assessments` | `require_content_creator!` | `value` + `scale` (server converts), optional `coach_profile_id` (D8/D9), rubric XOR, `status` defaults to `draft` |
| `PATCH /api/v1/assessments/:id` | `manageable_by?` | edits, status transitions, re-scoring; re-pointing `player_profile_id` is refused with 422 (an edit is not a merge) |

Request:

```json
{ "assessment": {
    "player_profile_id": 5, "coach_profile_id": 3, "skill_id": 7,
    "training_session_id": 9, "value": 4, "scale": "one_to_five",
    "status": "active", "notes": "Consistent platform; late on short serves." } }
```

Response (`201`):

```json
{ "id": 12, "player_profile_id": 5, "coach_profile_id": 3,
  "created_by": { "id": 2, "name": "Coach Ana" },
  "skill": { "id": 7, "title": "Forearm pass", "slug": "forearm-pass" },
  "custom_skill": null, "training_session_id": 9,
  "score": 70, "reported_value": 4, "scale": "one_to_five",
  "reported_score": 4, "ten_scale": 7, "five_scale": 4,
  "notes": "…", "status": "active", "created_at": "…", "updated_at": "…" }
```

Error shapes follow the existing convention: `{ "errors": [ … ] }` carrying
`errors.full_messages`, so the SPA's `ApiValidationError` renders them unchanged.
Integrity problems are 422, authority problems are 403, and a row that does not
exist for the caller is 404.

Additive payload keys — no existing key changes shape:

| Payload | Added |
| --- | --- |
| `GET /api/v1/players/:id` | `assessment_count` (active only) and `assessments` (the history the caller may see, newest first; drafts only for stakeholders) |
| `GET /api/v1/coaches/:id` | `assessments_recorded_count` and a recent slice |
| `GET /api/v1/training_sessions/:id` | per participant, the assessments recorded in that session |
| `GET /api/v1/me` | `person_id`, `coach_profile_id`, `player_profile_id` |

The `me` additions are what let the SPA default the assessor to the signed-in
coach, offer a "create my coach profile" path when there is none, and keep the
caller's own player profile out of the picker.

## SPA (4.3)

| File | Role |
| --- | --- |
| `src/utils/rating.ts` | mirror of `RatingScale` (live preview, badge rendering) |
| `src/utils/assessments.ts` | `canManageAssessments`, `ASSESSMENT_STATUSES`, `assessmentStatusLabel` — the shape `utils/training.ts` already uses |
| `src/components/people/ScoreBadge.tsx` | `70/100 · 7/10 · 4/5`, or "Not rated yet" |
| `src/components/people/AssessmentList.tsx` | latest per skill + history, Draft/Withdrawn tags, "recorded by …" |
| `src/components/people/AssessmentForm.tsx` | skill or free-text rubric (the `SkillFocusSelector` pattern), scale toggle with live preview, notes, optional session, coach picker for oversight (accountless coaches flagged from `account_status`), Save draft / Publish / Withdraw |
| `PlayerDetail`, `CoachDetail`, `TrainingDetail` | the three read surfaces, all inside `ManagerRoute` |

## Sub-phase work plan

| Step | Work | Gate |
| --- | --- | --- |
| 4.1.1–4.1.8 | this document · migration · `RatingScale` · `Assessment` · profile associations (`restrict_with_error`) · fixtures · service test · model test | `bin/rails test` |
| 4.2.9–4.2.15 | routes · controller · payload additions · `me` additions · controller tests · player/coach test extensions · session participants | `bin/rails test` |
| 4.3.16–4.3.23 | api types and calls · rating util · assessment utils · three components · three pages · CSS · SPA tests | `vitest` · `tsc -b` · `eslint .` · `vite build` |
| 4.4.24–4.4.26 | finalise this document · roadmap pointer in the identity model · assumptions · full gate | all five commands |

## Test plan

| Suite | Pins |
| --- | --- |
| `test/services/rating_scale_test.rb` | the 21-row matrix, both round-trips, monotonicity, rejection of illegal input, `describe` (including an unrated draft) |
| `test/models/assessment_test.rb` | rubric XOR both ways, score bounds, `reported_value` against its scale, the desync guard, publish-requires-score, **self-assessment invalid**, the existence/authority predicates (including that oversight is curator/admin and never a coach), and the referential rules — an **in-use skill cannot be hard-deleted**, a deleted session leaves the rating intact |
| `test/controllers/api/v1/assessments_controller_test.rb` | the existence and authority matrices, 404-not-403, every 422, the pagination envelope, `status`/`mine` filters, and the pinned `DELETE` 404 |
| players / coaches controller tests | the new payload keys, and that drafts never leak into them |
| SPA tests | the rating matrix, badge and list rendering, the form's conversion preview, the three page sections |

Fixture cast reused from the identity work: `users(:six)` (attributed coach,
`maria_coach`), `users(:three)` (coach who owns nothing), `users(:two)` (admin),
`users(:four)` (curator), `users(:one)` (player). Assessments use a dedicated
`skills(:assessment_rubric)` (in `categories(:two)`) so phase 4 never disturbs
this file's existing skill/category delete tests. Private players are created
inline with the `private_player_owned_by(user)` helper rather than in fixtures,
and the self-assessment case builds the dual-profile person inline so the
existing fixture counts are untouched.

## Assumptions (ratified, not implicit)

- The canonical score is an integer 0–100; the entry scale is recorded but never
  used to compare two assessments.
- The mappings are band-based per the tables above, not linear rounding.
- A `draft` or `withdrawn` row exists only for its stakeholders and oversight, and
  **no query parameter widens that**.
- Assessments are coach-authoritative and are never hard-deleted.
- Visibility is inherited from the player and is never authorization.
- Publishing requires a score, so an unrated row is a draft by definition.
- An assessment may be attributed to a coach whose Person has no account; those
  rows are managed by the recorder and by oversight.

## Out of scope

- Tournament results, `assertion_source` and dispute states (the roadmap groups
  them with tournaments).
- `PlayerCoach` join model and groups.
- `PersonClaim` / invitations, and `PersonMerge`.
- Deriving `player_profiles.level` from assessments (D23).
- A standalone assessments catalogue screen: Phase 4 is *integration*, so
  assessments surface on the player, coach and session pages.

## Related documents

- `docs/PERSON_IDENTITY_MODEL.md` — the identity model, the archive-not-delete
  rule, and the visibility convention this phase inherits.
- `docs/DATABASE_BACKUP_AND_RESTORE.md` — operational context for the new table.
