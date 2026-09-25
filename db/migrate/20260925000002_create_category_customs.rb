# Phase 5 (Assessment definitions): a custom category is a real record, not the
# free-text `custom_category` column Phase 4 kept on an assessment.
#
# The reason is authorization, not tidiness: "who may use this custom category"
# has nothing to reference while the text is an inline string. A row with
# `created_by` + `visibility` makes that rule checkable (see
# CategoryCustom.usable_by?), using the same shared/private pair the profile
# visibility work introduced.
class CreateCategoryCustoms < ActiveRecord::Migration[8.1]
  def change
    create_table :category_customs do |t|
      t.string :name, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :visibility, null: false, default: "shared"
      t.timestamps
    end

    add_check_constraint :category_customs,
                         "visibility IN ('shared', 'private')",
                         name: "category_customs_visibility"

    # One creator may not define the same custom category twice. Two different
    # coaches may both record "Mental game" for their own assessments — the name
    # is only unique within the creator's catalogue.
    add_index :category_customs, %i[created_by_id name],
              unique: true,
              name: "index_category_customs_on_creator_and_name"
    add_index :category_customs, :visibility
  end
end
