# Phase 6 (Assessment Sessions), plan S5: one scored line item inside a
# configured category — "Attack" is the weighted area, "Approach footwork" a
# criterion inside it.
#
# The table is created ahead of its use. Nothing scores against a criterion yet:
# today a configured category carries exactly one score row, so normalisation is
# still identity (D11). Creating the structure now is what lets a later criteria
# layer be filled in without another migration to the scoring tables — the
# companion migration `AddCriterionToAssessmentCategoryScores` does the rest.
#
# Criteria hang off the *configured category*, not the definition: §20's own
# example compares areas that carry different numbers of items ("one category
# contains 10 scored criteria and another contains 3"), so Attack's criteria are
# not Defence's.
class CreateCriteria < ActiveRecord::Migration[8.1]
  def change
    create_table :criteria do |t|
      t.references :assessment_category, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # Ordering is presentation only (never the maths), exactly like
    # `assessment_categories.position`.
    add_index :criteria, %i[assessment_category_id position]
    # The same item may not be listed twice under one area. Case-insensitive
    # uniqueness is left to the model (the DB index is the plain one, matching
    # how `category_customs` splits the two concerns).
    add_index :criteria, %i[assessment_category_id name], unique: true

    add_check_constraint :criteria, "position >= 0",
                         name: "criteria_position_non_negative"
  end
end
