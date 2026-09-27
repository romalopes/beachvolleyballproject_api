# Beach Volleyball Project — Assessment System Refactor

**Status:** Implemented. Definitions, sessions, scoring, ranking, consolidation and
groups (Phase A) all ship; criterion scoring (D16) and divisions remain deferred.

## Objective

Make the assessment lifecycle explicit and reusable:

```text
AssessmentDefinition → AssessmentSession → Add Players → Score Players
        ↓
Automatic Ranking → Publish Session → Ranking Consolidation (optional)
```

A definition describes what is assessed. A session is one coach's work with many players. A score row is an observation. A consolidation is a snapshot of several coaches' published results. These are separate concepts; the player page must not own assessment creation.

## 1. Current repository baseline

The repository already contains:

- `AssessmentDefinition` as a reusable weighted template.
- `AssessmentCategory` selecting exactly one standard `Category` or one `CategoryCustom`.
- Integer positive weights, ordered positions, duplicate-source protection, and active definitions totaling exactly 100.
- `AssessmentCategoryScore` for category-level inputs and `Assessment#score` for the derived weighted aggregate.
- The definition editor/API and legacy historical result readers.
- `Criterion`, its table, and nullable `assessment_category_scores.criterion_id` as forward-compatible scaffolding.
- `Group`, `GroupMembership`, and inline participant resolution as roster groundwork.
- A Player page that must remain read-only for assessments.

Do not rewrite the existing weighted-definition implementation merely to add sessions. Extend it and preserve historical behavior.

## 2. Revised Criterion decision

### Created now, not used for current scoring

`Criterion` is a real model and table now:

```text
AssessmentCategory
  └── has_many :criteria
Criterion
  └── belongs_to :assessment_category
AssessmentCategoryScore
  └── criterion_id (nullable, future use)
```

A criterion has a name, position, and association to its category. The score foreign key is nullable so existing category-level rows can remain valid. Model validation and partial indexes reserve the future shape: one category-level row while `criterion_id IS NULL`, and one row per criterion when criteria become active.

### Explicitly deferred

This phase does **not** enable criterion-based scoring:

- No definition editor creates criterion rows automatically.
- No API request accepts a criterion score.
- No grid renders criterion columns.
- No calculator reads `criterion_id`.
- No category score requires a criterion.
- No existing score is assigned a fabricated criterion.

The current effective model is one implicit criterion per category: each category has one category-level score. Normalization is therefore identity. A later phase can add criterion authoring, score UX, backfill/link strategy, and normalization without another migration to the scoring tables. Any genuinely new requirement-specific index or constraint must still receive a reviewed migration.

## 3. Canonical domain model

```text
AssessmentDefinition
  ├── AssessmentCategory[]
  │     ├── Category | CategoryCustom
  │     └── weight, position
  └── AssessmentSession[]
        ├── coach / User
        ├── optional Group
        └── PlayerAssessment[]
              ├── PlayerProfile
              ├── status, overall_score, rank
              └── Assessment[] (one per definition category)
                    └── AssessmentCategoryScore[] (one per category now)

RankingConsolidation
  ├── RankingConsolidationSession[] → AssessmentSession
  └── RankingConsolidationResult[] → PlayerProfile
        └── coach scores + average + final rank + division
```

### Definition rules

- A definition has name, description, scale, status, creator, timestamps, and ordered categories.
- Each category has exactly one source, positive integer weight, and presentation position.
- Draft definitions may have incomplete totals. Active definitions total exactly 100. Archived definitions remain readable.
- A referenced definition is frozen; duplicate it to make changes.
- Position never changes calculations.

### Session rules

- `AssessmentSession` belongs to one coach (`User`) and references one published `AssessmentDefinition`.
- It has name, date, draft/published/archived status, optional group, and timestamps.
- A draft may be edited by its coach or authorized oversight. A published session is immutable; corrections use a new session.
- Session and historical score rows are not hard-destroyed.
- A session may add existing players or create one inline through the shared `Person`/`PlayerProfile` path.
- A `Group` is a reusable roster only; membership does not imply attendance.

### Roster and result rules

`PlayerAssessment` is the join/result row for one session and one `PlayerProfile`. It stores roster position, status, `overall_score`, `rank`, and timestamps. It is not a new player identity model.

For a definition-backed session, create one legacy-compatible `Assessment` result per definition category, with its matching `AssessmentCategoryScore`. This preserves existing result and history readers while allowing a session to own many players and categories.

A missing category score is not zero. A player with incomplete required categories is `incomplete`, excluded from ranking, and reports missing categories in the API. A missing player in consolidation is handled by the consolidation policy, never silently treated as zero.


## 4. Authorization

Reuse the established authority matrix:

- Read: existing assessment/training-manager read policy.
- Definition create/update: existing content-creator/oversight policy.
- Session create: authorized coach for themselves unless oversight is explicitly allowed.
- Draft update: session owner or authorized oversight.
- Published update/delete: forbidden.
- Custom categories: existing creator/visibility rules.
- Player page: read-only history; no assessment mutation endpoint.

Controllers enforce authorization and validation server-side. Frontend gating is only usability.

## 5. Scoring and ranking

For a complete player:

```text
overall_score = Σ(category_score × category_weight / 100)
```

Use the existing project integer arithmetic/rounding convention. Never redistribute weights. A definition must total 100 before session publication.

The score grid is one column per `AssessmentCategory`, not one column per `Criterion`. Every `AssessmentCategoryScore` created in this phase has `criterion_id = NULL`.

Ranking rules:

- Calculate rankings server-side after a successful whole-grid save.
- Rank only complete rows.
- Use standard competition ranking: `1, 2, 2, 4`.
- Use deterministic secondary presentation ordering without changing rank.
- Persist `overall_score` and `rank` on the roster/result row.
- Reject publication if required rows are incomplete unless an explicit product rule says otherwise.

Saving a grid is atomic:

1. Authorize the draft session.
2. Validate every submitted cell and required category.
3. Begin a database transaction.
4. Create/update/delete score rows.
5. Recalculate all affected player aggregates.
6. Validate completeness and ranks.
7. Commit; roll back the entire grid on any error.

## 6. Persistence plan

Create the following tables, with foreign keys and indexes following current Rails/PostgreSQL conventions:

```text
assessment_sessions
  id, assessment_definition_id, user_id, group_id
  name, session_date, status, created_at, updated_at

player_assessments
  id, assessment_session_id, player_profile_id
  position, status, overall_score, rank, created_at, updated_at

ranking_consolidations
  id, name, status, created_by_id, created_at, updated_at

ranking_consolidation_sessions
  consolidation_id, assessment_session_id
```

## 7. Backend implementation order

### Models and migrations

Add models and associations for `AssessmentSession`, `PlayerAssessment`, and the consolidation tables. Add statuses, validations, authorization scopes, and dependent behavior. Keep historical rows readable. Put score aggregation in a service rather than a controller.

### API

Add endpoints under the existing `/api/v1` namespace:

```text
GET/POST       /assessment_sessions
GET/PATCH      /assessment_sessions/:id
POST           /assessment_sessions/:id/publish
POST           /assessment_sessions/:id/players
DELETE         /assessment_sessions/:id/players/:player_assessment_id
PUT            /assessment_sessions/:id/scores
GET            /assessment_sessions/:id/ranking

GET/POST       /ranking_consolidations
GET/PATCH      /ranking_consolidations/:id
POST           /ranking_consolidations/:id/sessions
POST           /ranking_consolidations/:id/generate
GET            /ranking_consolidations/:id/results
```

The session response must expose definition/category columns, roster status, missing categories, overall score, rank, and coach/session metadata. Score input is a full or explicitly partial grid with stable player and category IDs; never trust client-calculated totals.

### Consolidation

Allow consolidation only when every selected session is published and uses the same definition, scale, and definition snapshot. A compatible player list means every player appearing in any selected session is represented or reported as missing. Choose and document one policy: require every selected coach to score every player, or average available coach scores while exposing coverage. Never silently assign zero.

Generate a snapshot containing each coach's score, average, final rank, and division. Original session and player-assessment rows remain unchanged.

## 8. Frontend implementation

Remove the legacy player assessment form and all player-page assessment creation actions. Keep player assessment history as a read-only list linked to session/result views.

Add:

- `SessionWizard`: choose published definition, name/date, coach, optional group, then add players.
- `PlayerSelector`: search existing players and create a new player through the shared identity flow.
- `SpreadsheetScoreGrid`: rows are players, columns are weighted categories, with keyboard navigation and draft save.
- `SessionRankingTable`: overall score, rank, status, and missing-score indicators.
- `ConsolidationBuilder`: select compatible published sessions and generate a snapshot.
- `ConsolidationRanking`: coach scores, average, final rank, and division.

The grid displays category-level scores only. It does not display, require, or submit criteria in this phase. Disable publish in the UI when totals are not valid, but rely on backend validation as authoritative.

## 9. Testing and acceptance

Backend tests must cover:

- Definition/session creation, lifecycle, and authorization.
- Inline player creation and duplicate prevention.
- Group roster behavior and session/player uniqueness.
- Atomic grid save, rollback on invalid cell, and concurrent-safe updates.
- Category weighted totals, incomplete rows, ranking ties, and publication gating.
- Criterion tables/model validation without criterion-based score creation.
- Consolidation compatibility, missing-player policy, snapshot immutability, and no source-session mutation.
- Legacy historical assessment readability and read-only player history.

Frontend tests must cover:

- No assessment creation controls on the player page.
- Session wizard validation and player search/inline creation.
- Spreadsheet keyboard navigation and draft save/error recovery.
- Automatic overall and ranking updates.
- Publish gating and actionable weight/score messages.
- Consolidation compatibility and ranking display.
- Criterion UI is absent in this phase.

Definition of done:

```text
Player page: read-only history
Definitions: reusable, weighted, publish only at 100
Sessions: one coach, many players, atomic scoring, automatic ranking
Criteria: schema/model only; no active criterion scoring
Consolidation: snapshot-only, compatible sessions, explicit missing-score policy
```

## 10. Deferred follow-up

A later criteria phase may add definition-level criterion authoring, category-criterion ordering, criterion score validation, score-grid columns, normalized category aggregation, and a safe migration/link strategy for existing category-level scores. It must not silently reinterpret historical records or require the current phase to pretend criteria are already active.


## 11. Decision log

| # | Decision |
| --- | --- |
| D1 | Definition, session, player result, and consolidation are separate concepts. |
| D2 | The lifecycle is one-way: definition → session → scores → publish → optional consolidation. |
| D3 | The Player page is read-only for assessments and has no creation controls. |
| D4 | A session belongs to exactly one coach and may reference one optional group. |
| D5 | A referenced definition is frozen; duplicate it to make changes. |
| D6 | Sessions use draft, published, and archived statuses. Only published sessions may be consolidated. |
| D7 | Rosters reuse the existing Person and PlayerProfile identity model. |
| D8 | `PlayerAssessment` is the session/player join and stores derived score and rank. |
| D9 | Inline player creation uses the existing participant/person-creation service path. |
| D10 | Inline matching is idempotent according to existing project matching rules. |
| D11 | Scoring this phase is one canonical score per `AssessmentCategory`; `Criterion` is not consulted. |
| D12 | Weighted aggregate remains in the existing result/score architecture; do not introduce a second source of truth. |
| D13 | A session requires a published definition and cannot be published with missing required scores. |
| D14 | Missing scores are never zero: rows are incomplete and excluded from ranking. |
| D15 | Ranking uses standard competition ranking over complete rows. |
| D16 | `Criterion` and nullable `criterion_id` land now, but criterion scoring is deliberately deferred. |
| D17 | Future criteria belong to a category or custom category, exactly one source. |
| D18 | The score grid is one column per category and does not send `criterion_id`. |
| D19 | Score-grid writes are validated and recalculated server-side in one transaction. |
| D20 | Consolidations validate definition, publication status, and session existence; roster gaps are reported, never refused. |
| D21 | A consolidation never blocks over missing or incomplete players. It always merges, always averages over the sessions that scored the player, exposes `coverage` per row, and stores a per-session `source_warnings` list. Nothing is ever assigned zero. |
| D22 | Consolidation stores coach scores, coverage, average, and rank as an immutable snapshot. Division was considered and explicitly deferred (see §14). |
| D23 | Groups are reusable roster containers and have no scoring semantics. |
| D24 | Published sessions and consolidations are archival; corrections create new records. |
| D25 | Weight percentages remain positive integers and published definitions total exactly 100. |

## 12. Final acceptance checklist

Verified 2026-09-27 (backend `971 runs / 3681 assertions / 0 failures`, frontend
`690 tests`, `npm run build`, `eslint src` clean, `rubocop` clean on touched files,
`db:migrate` status `up`).

- [x] No assessment creation workflow remains on the player page.
      `PlayerDetail` renders the read-only `AssessmentList`; `api.createAssessment` is
      declared in `src/api.ts` but has no caller anywhere.
- [x] Definitions are reusable weighted templates and publish only at 100%.
      `assessment_definitions_controller_test.rb` — "create refuses to activate an
      unbalanced definition, naming the total"; `remaining_weight` returned on read.
- [x] A coach can create one session and add many existing or inline-created players.
      Roster controller tests plus `AssessmentSessionRoster.test.tsx` (add, dedupe,
      inline creation, published lock).
- [x] Score saving is transactional and calculates weighted totals server-side.
      D19; `SpreadsheetScoreGrid.test.tsx` (save payloads, invalid values, server
      errors) and the scores controller tests.
- [x] Rankings exclude incomplete rows and handle ties deterministically.
      D14/D15; `SessionRankingTable.test.tsx` (ranks, ties, missing categories,
      exclusions).
- [x] Sessions and consolidations enforce authorization server-side.
      Controller tests refuse guest, player and curator roles on both resources.
- [x] Consolidations are compatible-session snapshots and never mutate source sessions.
      "withdrawing a source session leaves the consolidation unchanged", plus the
      builder's "warnings are stored on the row rather than recomputed from the source".
- [x] Criterion tables/model/nullable score column exist, but criterion scoring is absent.
      `assessment_category_scores.criterion_id` is nullable with a partial unique index
      (`where: criterion_id IS NOT NULL`); D16 defers the scoring side.
- [x] Existing historical assessments remain readable and unchanged.
      `assessment_session_test.rb` asserts "the historical result must survive";
      `assessments_controller_test.rb` asserts legacy rows keep their single rubric.
- [x] Backend and frontend tests, build, lint, and migration checks pass.
      See the summary line above.

## 13. Implementation notes and deviations (Phase 4.3.3.6)

- **API surface.** §8 specified `PATCH /ranking_consolidations/:id`, `POST /:id/sessions`,
  `POST /:id/generate` and `GET /:id/results`. Only `index`, `show` and `create` are
  implemented, deliberately: consolidation rows are an immutable snapshot (D22, D24), so an
  update, a session-mutation or a regenerate endpoint would let a snapshot change after the
  fact. `show` already returns every row with its per-session scores, so a separate `results`
  endpoint would be redundant.
- **Scale validation.** D20 listed `scale` as a validated attribute, but no scale column
  exists on `assessment_definitions` — a definition's categories carry their scale
  implicitly. Comparing `assessment_definition_id` therefore implies equal scale, so no
  separate check is made.
- **Missing players (D21).** The builder originally raised when a source session had
  incomplete players. Under the ratified policy it no longer blocks: an incomplete player is
  simply absent from that session's ranking snapshot, so their row's `coverage` falls below
  `session_count`, the session is recorded in `source_warnings`, and the UI badges both.
  A session with *no* scored players contributes a warning but still merges — no player is
  ever assigned zero.

## 14. Deferred work

- **Divisions (AAA / AA / A).** Originally part of D22 and now explicitly out of scope.
  No thresholds exist anywhere in the product, and inventing cut-offs would silently encode
  policy into real athlete rankings. Deferred until the club defines the bands. When picked
  up: a `division` column on `ranking_consolidation_rows`, a `RatingDivision` value object,
  computation inside `RankingConsolidationBuilder`, and a column in the ranking table.
- **Criterion scoring** (D16) remains deferred as previously decided.
- ~~**Groups UI** (D23)~~ — **implemented in Phase A.** See §15.

## 15. Groups (Phase A, D23)

Groups are now a real, end-to-end feature rather than schema groundwork. The rule
from §3 is unchanged and still the reason for every decision below: **a group is
a reusable roster only. Membership is not attendance, and confers no access.**

### Model

`Group` gained the pieces the catalogue needed and nothing it did not:

- `has_many :assessment_sessions, dependent: :restrict_with_error` — the
  archive-not-delete rule stated in the model comment is now enforced by the
  database layer, so a group that has run sessions cannot be destroyed at all.
- `scope :owned_by` and `#owner?` for the ownership checks.
- `#visible_to_user?` as the single source of truth for the soft-visibility
  decision, mirroring `PlayerProfile#visible_to_user?`. A hidden group answers
  **404, not 403**: whether a private squad exists is itself information.

No status column was added to `GroupMembership`, and no scoring field to `Group`.
Anything more transient than "is in this squad" belongs to the session that
observed it.

### API

`Api::V1::GroupsController`, routed as `resources :groups, except: %i[new edit]`
plus `POST /groups/:id/members` and `DELETE /groups/:id/members/:player_profile_id`.

Authorization follows the three gates the rest of the catalogue uses: read is
`require_training_manager!` (coach/curator/admin); create, update, destroy and
membership changes are `require_content_creator!` (coach/admin); and update or
destroy additionally requires owner-or-admin, so one coach's roster cannot be
rewritten by another. The curators who may *see* every group are deliberately not
allowed to *mint* one, matching `RankingConsolidationsController`.

`index` supports `q`, `status` (`active` default, `archived`, `all`), `mine` and
`include_private`, and returns the standard `{ data, meta }` envelope. `show`
resolves an id **or** a slug and adds the roster rows. Destroying a group that
has already run sessions is refused with 422 naming archive as the alternative,
rather than 404ing the route.

### Session integration

`AssessmentSessionsController#create` seeds the roster from the chosen group:
every member becomes an `included` participant. This is the whole point of a
group, and it is safe precisely because membership is not attendance — the coach
still removes anyone who did not show up, and the roster remains editable while
the session is a draft. The wizard's group picker is optional and defaults to
none, and the hint under it says membership is not attendance rather than
leaving a coach to wonder whether the roster is now fixed.

### Frontend

- `Groups` page: catalogue with search, a "Show archived" toggle, and
  per-row Edit / Archive / Delete. The editor holds a bounded checkbox roster
  picker that reuses the consolidation session-picker styles.
- `api.groups` / `api.group` / `api.createGroup` / `api.updateGroup` /
  `api.deleteGroup` / `api.addGroupMembers` / `api.removeGroupMember`.
  `updateGroup` omits the roster entirely when no ids are passed and sends `[]`
  to clear it, so "I only renamed this" cannot silently wipe a squad.
- The roster picker requests `include_private`, because visibility is
  presentation and never blocks scheduling — the same rule the training form's
  player picker already follows.

Verified with the Phase A gate: backend `995 runs / 3769 assertions / 0 failures`
(of which 22 are the new `groups_controller_test.rb` and 2 the new model tests),
frontend `73 files / 703 tests`, `npm run build`, `eslint src` clean, and
`rubocop` clean on every touched file.

