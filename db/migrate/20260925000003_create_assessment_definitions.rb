# Phase 5: the reusable weighted configuration ("A-Level Assessment" = Attack
# 40 · Defense 30 · Serve 20 · Strategy 10).
#
# A definition is club-level configuration, deliberately separate from
# Assessment: an Assessment is one coach's rating of one player (Phase 4) and
# must keep its player/coach/result shape, while a definition is authored once
# and applied to many players.
#
# `status` mirrors TrainingSession's draft-first workflow: `draft` may be
# unbalanced while it is being built, `active` is the only status that may be
# attached to an assessment, and `archived` keeps every historical result
# readable without allowing new ones — nothing here is ever hard-deleted.
class CreateAssessmentDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :assessment_definitions do |t|
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.text :description
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :assessment_definitions, :status
    add_index :assessment_definitions, :name

    add_check_constraint :assessment_definitions,
                         "status IN ('draft', 'active', 'archived')",
                         name: "assessment_definitions_status"
  end
end
