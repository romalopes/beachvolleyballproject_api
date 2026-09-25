# Phase 5: one configured category within an assessment definition, with the
# weight that category contributes to the aggregate.
#
# The join belongs to the *definition* (column `assessment_definition_id`), not
# to an assessment: `assessments` is the per-player result table, and naming
# this after `assessment_id` would have been ambiguous about which of the two
# things a category configures.
#
# Three rules are encoded straight into the table (they are the whole point of
# the model and must not depend on validation being run):
#   * a row is exactly one source — a standard Category XOR a custom one;
#   * a weight is a positive integer percent (this schema has no decimal
#     columns at all, and nothing in the product asks for fractional weights);
#   * the same source may not appear twice in one definition, which the two
#     partial unique indexes below enforce far more reliably than validation.
class CreateAssessmentCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :assessment_categories do |t|
      t.references :assessment_definition, null: false, foreign_key: true
      t.references :category, foreign_key: true
      t.references :category_custom, foreign_key: true
      t.integer :weight, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_check_constraint :assessment_categories,
                         "(category_id IS NOT NULL AND category_custom_id IS NULL) OR " \
                         "(category_id IS NULL AND category_custom_id IS NOT NULL)",
                         name: "assessment_categories_source_xor"
    add_check_constraint :assessment_categories,
                         "weight > 0",
                         name: "assessment_categories_weight_positive"
    add_check_constraint :assessment_categories,
                         "position >= 0",
                         name: "assessment_categories_position_non_negative"

    add_index :assessment_categories, %i[assessment_definition_id category_id],
              unique: true,
              where: "category_id IS NOT NULL",
              name: "index_assessment_categories_on_definition_and_category"
    add_index :assessment_categories, %i[assessment_definition_id category_custom_id],
              unique: true,
              where: "category_custom_id IS NOT NULL",
              name: "index_assessment_categories_on_definition_and_custom"
  end
end
