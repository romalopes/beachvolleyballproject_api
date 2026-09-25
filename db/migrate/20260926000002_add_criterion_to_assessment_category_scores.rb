# Phase 6 (Assessment Sessions), plan S5: make room for a criteria layer without
# moving the goalposts today.
#
# The index replaced here was `[assessment_id, assessment_category_id]` — "at
# most one score row per configured category". That is precisely the rule a
# criteria layer would have to migrate *away* the day criteria are scored, so it
# is expressed here in a form that already fits both worlds:
#
#   * `criterion_id IS NULL`  → one row per category. Every row today is in this
#     state, so the constraint is behaviourally identical to the full index it
#     replaces: two rows for the same category are still refused.
#   * `criterion_id IS NOT NULL` → one row per criterion. Permitted from now on
#     but unused, so a later phase adds rows without touching this table again.
#
# `criterion_id` is nullable on purpose: NULL means "this row is the whole
# area", which is what keeps a category carrying exactly one number and
# normalisation an identity (D11).
#
# The column also exists so that "a criterion must belong to the area it
# scores" can be enforced by validation from day one — a rule worth having
# before there is any UI able to break it.
class AddCriterionToAssessmentCategoryScores < ActiveRecord::Migration[8.1]
  def change
    add_reference :assessment_category_scores, :criterion, null: true, foreign_key: true

    remove_index :assessment_category_scores,
                 name: "index_assessment_category_scores_on_assessment_and_category"

    # One row per category (today's rule, every row qualifies).
    add_index :assessment_category_scores, %i[assessment_id assessment_category_id],
              unique: true,
              where: "criterion_id IS NULL",
              name: "index_assessment_category_scores_on_assessment_and_category"

    # One row per criterion within a category (the layer this column enables).
    # The name is abbreviated because the generated form
    # (`..._on_assessment_category_and_criterion`) is 69 characters, past
    # PostgreSQL's 63-character identifier limit.
    add_index :assessment_category_scores,
              %i[assessment_id assessment_category_id criterion_id],
              unique: true,
              where: "criterion_id IS NOT NULL",
              name: "index_assessment_category_scores_on_category_and_criterion"
  end
end
