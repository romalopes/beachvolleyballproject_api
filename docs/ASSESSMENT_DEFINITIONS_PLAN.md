# Assessment Definitions Plan (Phase 5)

> **Status: approved design; implementation in progress.** This document is the
> contract for multi-category weighted assessments: the entities, the invariants,
> the weight rules and the calculation. It supersedes nothing in
> `ASSESSMENT_INTEGRATION_PLAN.md` — Phase 4's per-player ratings stay exactly as
> they are (see D12).

How a coach defines a *reusable, weighted assessment* ("A-Level Assessment" =
Attack 40 · Defense 30 · Serve 20 · Strategy 10) and then applies it to a
player to produce one weighted score.

## Why this phase

Phase 4 built `Assessment` as **one coach's rating of one player against one
rubric**. That is a result, not a definition. Nothing in the codebase can express
"these five areas matter, in these proportions" — there is no `Criterion`, no
`AssessmentArea`, no weight anywhere in the schema, and "custom category" is a
free-text column rather than a record.

This phase adds the *definition* half of that idea, while leaving every existing
rating, payload key and UI surface working untouched.

## Decision log

| # | Decision |
| --- | --- |
| D1 | A **definition** and a **result** are different things. `AssessmentDefinition` is the reusable weighted template; `Assessment` remains the per-player, per-coach result |
| D2 | `assessment_categories` belongs to the **definition**, not to a result — column `assessment_definition_id`. (`assessments` is the result table; naming the join after `assessment_id` would have been ambiguous) |
| D3 | A weight is an **integer percent > 0**. This codebase has no decimal/numeric columns at all, and every rating is an integer — introducing `decimal(5,2)` for one field would be a new numeric convention for no product requirement yet |
| D4 | The weights of an **active** definition must total exactly **100**; a **draft** may total anything (the editor shows remaining / over-allocated). Weights are never auto-balanced |
| D5 | The same category (or custom category) may appear **at most once** per definition — enforced by two partial unique indexes, not just validation |
| D6 | Definition statuses are `draft`, `active`, `archived`. Only an `active` definition may be attached to a new assessment; `archived` keeps every historical result readable |
| D7 | A definition that any assessment references is **frozen**: its configuration may not be edited or deleted (422 with "duplicate it to make changes"). Archive instead |
| D8 | `CategoryCustom` becomes a **real model** (`name`, `created_by`, `visibility`) so "who may use this custom category" is checkable. Free-text `custom_category` on legacy rows stays as-is (D12) |
| D9 | The weighted aggregate is stored in `assessments.score` (canonical 0..100). The children hold the inputs; the parent holds the derived result. No competing source of truth |
| D10 | For a definition-based row, `reported_value`/`scale` live **per child** (a coach may type 1–5 for one area and 1–100 for another); the parent's `scale` becomes nullable and unused |
| D11 | **Normalisation is identity today.** One category carries exactly one canonical 0..100 score, so there is nothing to normalise. If a criteria/items layer is ever added, normalisation moves to `AssessmentCategoryScore` and the formula below is unchanged |
| D12 | **Legacy rows are untouched.** No backfill, no recalculation: an existing single-rubric row keeps its rubric, its score, its payload keys and its UI |
| D13 | Authority reuses Phase 4: read = `require_training_manager!`, create = `require_content_creator!`, edit = owner ∪ oversight (`Assessment.oversight?` = curator/admin) |
| D14 | `position` is presentation order only — it never enters the calculation. Missing positions are filled from array index, exactly like training focuses |

## Domain model

```text
CategoryCustom ──┐
Category ────────┴──< AssessmentCategory >── AssessmentDefinition
                           │                      name, status, created_by
                           ├ weight (integer %)
                           └ position (presentation only)
                                                   ▲
                                     assessment_definition_id
                                                   │
              Assessment ──────────────────────────┘
              player_profile + coach_profile + score + status      (the result)
                    │
                    └──< AssessmentCategoryScore >── AssessmentCategory
                            score / reported_value / scale / notes
```

### Two kinds of `Assessment` row

| | `assessment_definition_id` | rubric columns | children |
| --- | --- | --- | --- |
| **Legacy (Phase 4)** | NULL | `category_id` XOR `custom_category` | none |
| **Definition-based** | present | both NULL | `assessment_category_scores` |

Enforced in the database:

```sql
assessment_definition_id IS NULL
  OR (category_id IS NULL AND custom_category IS NULL)
```

## Calculation

```text
weighted_score = round( Σ (category_score_i × weight_i) / 100 )
```

`80×0.40 + 70×0.30 + 90×0.30 = 80`. Children are scored first, then the parent
aggregate is recomputed and stored in `assessments.score`. Order of categories
has no effect (D14).

## Publish rules

An assessment using a definition may be `active` only when **all** of its
categories carry a score and the definition is balanced (D4):

```text
children.count == definition.assessment_categories.count
all children scored
definition.status == active   (an archived configuration keeps old results
                               readable but cannot host a new publication)
```

A **draft** result may be incomplete — some categories unscored — which mirrors
Phase 4's unrated-draft rule. The message always names the number:

```text
The assessment weights must total 100%. Current total: 85%.
```

## Custom categories

`CategoryCustom(name, created_by_id, visibility)` with `shared`/`private`
visibility (the same pair `ProfileVisibility` already uses).

`CategoryCustom.usable_by?(user)`:

* oversight (curator/admin) → always
* `shared` → any content creator
* `private` → its creator only

A referenced custom category cannot be hard-deleted (`restrict_with_error`),
matching the rule that an in-use `Category` cannot be deleted.

## API

| Endpoint | Who | Contract |
| --- | --- | --- |
| `GET /api/v1/assessment_definitions?status=` | training manager | paginated envelope |
| `GET /api/v1/assessment_definitions/:id` | training manager | includes ordered `assessment_categories` |
| `POST /api/v1/assessment_definitions` | content creator | nested `assessment_categories_attributes` |
| `PATCH /api/v1/assessment_definitions/:id` | owner ∪ oversight | **422 when the definition has results** (D7) |
| `PATCH /api/v1/assessment_definitions/:id/reorder` | owner ∪ oversight | `{ ids: [...] }`, the `video_tags` convention |
| `GET/POST/PATCH /api/v1/category_customs` | manager / creator / owner-oversight | `usable_by?` gates selection |
| `POST/PATCH /api/v1/assessments` | unchanged | either legacy rubric fields **or** `assessment_definition_id` + nested `assessment_category_scores_attributes` |

Nested category sets are assigned inside one `ActiveRecord::Base.transaction`:
validate the submitted set, apply create/update/destroy, re-check the total,
commit — any failure rolls the whole configuration back. Positions missing from
the payload are filled from array index (`fill_missing_positions!` idiom).
Errors keep the existing `{ "errors": [ … ] }` shape so `ApiValidationError`
renders them unchanged.

## SPA surface

| File | Role |
| --- | --- |
| `pages/assessments/AssessmentDefinitions.tsx` | list + create/edit (`/assessments/definitions`) under `ManagerRoute` |
| `components/assessments/AssessmentCategoryEditor.tsx` | rows: source, weight, add/remove, reorder (up/down, the `SkillFocusSelector` pattern) |
| `components/assessments/WeightTotalIndicator.tsx` | `Total: 85% · 15% remaining` / `20% over allocated` / `Total: 100%` |
| `components/assessments/CategoryCustomPicker.tsx` | add standard or custom categories, hiding ones already chosen |
| `AssessmentForm` | gains a definition mode with per-category score entry; the legacy rubric path stays for coaches without definitions |
| `AssessmentList` / `ScoreBadge` | weighted total plus per-category breakdown for definition rows |

## Migration and history preservation

Five migrations, each reversible: `create_category_customs`,
`create_assessment_definitions`, `create_assessment_categories`,
`create_assessment_category_scores`, `add_definition_support_to_assessments`.

The last one is the only one that touches `assessments`: it adds a nullable FK
and **relaxes** three constraints so a derived aggregate can exist without a
typed counterpart (D9/D10). No row is rewritten, no score is recomputed, and
Phase 4 payload keys keep their exact shape (D12).

## Assumptions (ratified, not implicit)

- Integer weights; fractional weights are a one-line schema change if the club
  ever needs them, but nothing today asks for `12.5`.
- One score per category per result — criteria/skills/drills do **not** feed
  assessment scoring (they feed training).
- Definitions are club-level configuration, not per-player objects; a result
  always names the player and the attributed coach as before.
- Nothing is hard-deleted: definitions archive, custom categories refuse to
  disappear while referenced, assessments are withdrawn.

## Out of scope

- A criteria/questions layer and normalisation across criteria (D11 records the
  extension point; no `Criterion` model exists).
- Re-deriving `player_profiles.level` from assessments (Phase 4, D23).
- Tournament results, `assertion_source`, dispute states.
- Editing a frozen definition in place (D7 explicitly routes that to duplicate).

## Sub-phase plan

| Step | Work | Gate |
| --- | --- | --- |
| 5.0 | this document | review |
| 5.1 | migrations · `CategoryCustom` · `AssessmentDefinition` · `AssessmentCategory` · `AssessmentCategoryScore` · `Assessment` constraint relaxation · fixtures · model tests | `bin/rails test` |
| 5.2 | routes · two controllers · nested atomic updates · serialization · request tests | `bin/rails test` |
| 5.3 | SPA types/calls · definition pages · editor · total indicator · SPA tests | `vitest` · `tsc -b` · `eslint .` · `vite build` |
| 5.4 | weighted display in `AssessmentForm` / list / badge · page sections · tests | same four |
| 5.5 | roadmap pointers · full gate on both repositories | all five commands |

All work is left **uncommitted** for review.
