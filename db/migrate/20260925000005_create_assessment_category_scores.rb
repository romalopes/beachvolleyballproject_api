# Phase 5: what the coach scored for one configured category of an applied
# assessment definition.
#
# The typed entry lives here, per category (a coach may enter 1–5 for one area
# and 1–100 for another), and the parent Assessment stores only the derived
# weighted aggregate. The children are inputs; the parent is the result.
#
# Both foreign keys are restrictive on purpose:
#   * assessments are never hard-deleted (Phase 4, D18);
#   * a definition's configuration is frozen once it has results, so a scored
#     category cannot be dropped out from under its history.
class CreateAssessmentCategoryScores < ActiveRecord::Migration[8.1]
  def change
    create_table :assessment_category_scores do |t|
      t.references :assessment, null: false, foreign_key: true
      t.references :assessment_category, null: false, foreign_key: true
      t.integer :score
      t.integer :reported_value
      t.string :scale, null: false, default: "one_to_ten"
      t.text :notes
      t.timestamps
    end

    add_index :assessment_category_scores, %i[assessment_id assessment_category_id],
              unique: true,
              name: "index_assessment_category_scores_on_assessment_and_category"

    add_check_constraint :assessment_category_scores,
                         "score IS NULL OR (score >= 0 AND score <= 100)",
                         name: "assessment_category_scores_score_range"
    add_check_constraint :assessment_category_scores,
                         "(score IS NULL) = (reported_value IS NULL)",
                         name: "assessment_category_scores_score_pair"
    add_check_constraint :assessment_category_scores,
                         "scale IN ('one_to_five', 'one_to_ten', 'one_to_hundred')",
                         name: "assessment_category_scores_scale"
  end
end
