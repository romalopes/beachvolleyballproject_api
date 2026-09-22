# Phase 2 (follow-up): the `visibility` addition was appended to migration
# 20260922000003 after that migration had already run in development and
# test databases, so the column was never created. This follow-up adds it;
# guards keep it idempotent on databases where 0003 already applied fully.
class AddVisibilityToTrainingSessions < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:training_sessions, :visibility)
      add_column :training_sessions, :visibility, :string, null: false, default: "shared"
    end
    unless index_exists?(:training_sessions, :visibility)
      add_index :training_sessions, :visibility
    end
  end

  def down
    remove_index :training_sessions, :visibility if index_exists?(:training_sessions, :visibility)
    remove_column :training_sessions, :visibility if column_exists?(:training_sessions, :visibility)
  end
end
