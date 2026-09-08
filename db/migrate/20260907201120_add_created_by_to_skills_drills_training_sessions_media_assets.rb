class AddCreatedByToSkillsDrillsTrainingSessionsMediaAssets < ActiveRecord::Migration[8.1]
  def change
    add_reference :skills, :created_by, null: true, foreign_key: { to_table: :users }
    add_reference :drills, :created_by, null: true, foreign_key: { to_table: :users }
    add_reference :training_sessions, :created_by, null: true, foreign_key: { to_table: :users }
    add_reference :media_assets, :uploaded_by, null: true, foreign_key: { to_table: :users }
  end
end
