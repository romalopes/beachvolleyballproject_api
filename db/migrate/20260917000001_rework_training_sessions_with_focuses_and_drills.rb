# Reworks the legacy single-drill TrainingSession into the shared training
# schedule model:
#
#   TrainingSession -> TrainingFocus            (skill-based or custom-text focus)
#   TrainingSession -> TrainingSessionDrill     (ordered drills with session-specific
#                                                duration/notes; the Drill is only
#                                                referenced, never duplicated, so
#                                                future DrillVersioning can slot in
#                                                between the join row and the drill)
#   TrainingSession -> TrainingSessionMediaAsset (future media extension point)
#
# `created_by_id` is kept as an audit field only; visibility/management is
# role-based (coach/curator/admin) and does not key off the creator.
#
# Existing rows are migrated: title from the referenced drill, starts_at from
# scheduled_at, and each legacy drill assignment is preserved as an ordered
# training_session_drills row.
class ReworkTrainingSessionsWithFocusesAndDrills < ActiveRecord::Migration[8.1]
  def up
    # 1. New columns, added nullable so existing rows can be backfilled.
    add_column :training_sessions, :title, :string
    add_column :training_sessions, :description, :text
    add_column :training_sessions, :starts_at, :datetime
    add_column :training_sessions, :ends_at, :datetime
    add_column :training_sessions, :status, :string, null: false, default: "draft"

    # 2. Backfill from the legacy shape (drill_id / scheduled_at / notes).
    execute <<~SQL
      UPDATE training_sessions
         SET title = drills.title,
             description = COALESCE(training_sessions.notes, drills.setup_instructions),
             starts_at = COALESCE(training_sessions.scheduled_at, NOW()),
             ends_at = COALESCE(training_sessions.scheduled_at, NOW()) + INTERVAL '1 hour'
        FROM drills
       WHERE drills.id = training_sessions.drill_id
    SQL
    execute "UPDATE training_sessions SET title = 'Training Session' WHERE title IS NULL"
    execute <<~SQL
      UPDATE training_sessions
         SET starts_at = NOW(),
             ends_at = NOW() + INTERVAL '1 hour'
       WHERE starts_at IS NULL
    SQL
    execute "UPDATE training_sessions SET ends_at = starts_at + INTERVAL '1 hour' WHERE ends_at IS NULL"

    change_column_null :training_sessions, :title, false
    change_column_null :training_sessions, :starts_at, false
    change_column_null :training_sessions, :ends_at, false

    add_index :training_sessions, :starts_at
    add_index :training_sessions, :status

    create_focuses_table
    create_session_drills_table

    # Preserve legacy drill assignments before dropping the legacy columns.
    execute <<~SQL
      INSERT INTO training_session_drills
                  (training_session_id, drill_id, position, created_at, updated_at)
      SELECT id, drill_id, 0, NOW(), NOW()
        FROM training_sessions
       WHERE drill_id IS NOT NULL
    SQL

    remove_reference :training_sessions, :drill, foreign_key: true
    remove_column :training_sessions, :scheduled_at
    remove_column :training_sessions, :notes

    create_session_media_assets_table
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "TrainingSession was reworked from the single-drill shape; restore from a backup"
  end

  private

  # Focuses: either an existing Skill or custom text, never both.
  def create_focuses_table
    create_table :training_focuses do |t|
      t.references :training_session, null: false, foreign_key: true
      t.references :skill, null: true, foreign_key: true
      t.string :custom_focus
      t.text :description
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    # Skill-based focuses are unique within a training. A nullable skill_id
    # keeps custom-text focuses out of the constraint (Postgres treats NULLs as
    # distinct, so any number of custom focuses are allowed).
    add_index :training_focuses, [ :training_session_id, :skill_id ],
              unique: true,
              name: "index_training_focuses_on_session_and_skill"
    add_index :training_focuses, [ :training_session_id, :position ],
              name: "index_training_focuses_on_session_and_position"
  end

  # Ordered drills belonging to a training session.
  def create_session_drills_table
    create_table :training_session_drills do |t|
      t.references :training_session, null: false, foreign_key: true
      t.references :drill, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.integer :duration_minutes
      t.text :notes

      t.timestamps
    end
    add_index :training_session_drills, [ :training_session_id, :drill_id ],
              unique: true,
              name: "index_training_session_drills_on_session_and_drill"
    add_index :training_session_drills, [ :training_session_id, :position ],
              name: "index_training_session_drills_on_session_and_position"
  end

  # Future media extension point. Reuses the existing MediaAsset model; no
  # training-specific media model is introduced.
  def create_session_media_assets_table
    create_table :training_session_media_assets do |t|
      t.references :training_session, null: false, foreign_key: true
      t.references :media_asset, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :title

      t.timestamps
    end
    add_index :training_session_media_assets, [ :training_session_id, :media_asset_id ],
              unique: true,
              name: "index_training_session_media_assets_on_session_and_asset"
    add_index :training_session_media_assets, [ :training_session_id, :position ],
              name: "index_training_session_media_assets_on_session_and_position"
  end
end
