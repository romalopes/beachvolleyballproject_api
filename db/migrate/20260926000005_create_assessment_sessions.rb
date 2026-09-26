# Phase 2 (Assessment Sessions), plan S1/§2: one coach evaluating MANY players
# in one sitting.
#
# Deliberately a standalone model, not a TrainingSession: a training is a
# schedule entry, an assessment session is the act of rating a roster against a
# weighted definition. Mixing them would make "cancelled training" mean
# "incomplete assessment", so the two are joined by no foreign key at all.
#
# The definition is the *template* being applied, so it must already be `active`
# (and frozen) before results start quoting it. `coach_profile_id` is the coach
# of record — an assessment always names a domain coach, never an account.
# `created_by` is audit only, never an ownership boundary.
#
# `withdrawn` is deliberately separate from `published`: a retracted number about
# a player is more sensitive than a cancelled schedule entry, so a published
# session stays archival and leaves the club's view by being withdrawn.
class CreateAssessmentSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :assessment_sessions do |t|
      t.references :assessment_definition, null: false, foreign_key: true
      t.references :coach_profile, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :group, foreign_key: true

      t.string :name
      t.date :scheduled_on
      t.string :status, null: false, default: "draft"
      t.text :notes
      t.datetime :published_at

      t.timestamps
    end

    add_index :assessment_sessions, :status
    add_index :assessment_sessions, :scheduled_on

    add_check_constraint :assessment_sessions,
                         "status IN ('draft', 'published', 'withdrawn')",
                         name: "assessment_sessions_status"
    add_check_constraint :assessment_sessions,
                         "status <> 'published' OR published_at IS NOT NULL",
                         name: "assessment_sessions_published_requires_timestamp"
  end
end