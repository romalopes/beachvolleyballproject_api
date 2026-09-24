# Phase 4 (Assessment integration): what a coach observed a player do, against a
# skill.
#
# Two decisions are encoded straight into the table:
#   * both profiles are NOT NULL — an assessment is always about a
#     PlayerProfile and always attributed to a CoachProfile, never to a bare
#     Person or a User;
#   * `score` is the canonical 0..100 rating, while the coach's own entry is kept
#     in `reported_value` + `scale`. Keeping the typed value is what makes a
#     later change to the band table a data migration instead of a guess.
#
# The status constraint mirrors `training_sessions_status`: `draft` rows are not
# club knowledge yet, `active` rows are, and `withdrawn` retracts one without
# destroying it — nothing in this project is ever hard-deleted.
class CreateAssessments < ActiveRecord::Migration[8.1]
  def change
    create_table :assessments do |t|
      t.references :player_profile, null: false, foreign_key: true
      t.references :coach_profile, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :skill, foreign_key: true
      t.string :custom_skill
      # A session is a pointer, not a claim. Deleting a session is a hard delete
      # (the only kind this project performs, and only on shared content), and it
      # must neither destroy nor block the assessments recorded during it — the
      # same reasoning VideoCategory models with `on_delete: :nullify`. A skill is
      # deliberately NOT nullified: it is the rubric, and the XOR constraint below
      # requires one, so an in-use skill simply cannot be deleted.
      t.references :training_session, foreign_key: { on_delete: :nullify }

      # The canonical rating and the coach's own input. Both are NULL only while
      # the row is a draft — an assignment the coach has not rated yet.
      t.integer :score
      t.integer :reported_value
      t.string :scale, null: false, default: "one_to_ten"

      t.text :notes
      t.string :status, null: false, default: "draft"

      t.timestamps
    end

    add_index :assessments, %i[player_profile_id created_at]
    add_index :assessments, :status

    add_check_constraint :assessments,
                         "status IN ('draft', 'active', 'withdrawn')",
                         name: "assessments_status"

    add_check_constraint :assessments,
                         "score IS NULL OR (score >= 0 AND score <= 100)",
                         name: "assessments_score_range"

    # Either both numbers are present or neither is: a half-filled rating would
    # have no meaning, and the pair is what keeps the conversion auditable.
    add_check_constraint :assessments,
                         "(score IS NULL) = (reported_value IS NULL)",
                         name: "assessments_score_pair"

    # Publishing requires a score: an unrated row is a draft by definition, so a
    # published assessment can never read as an evaluation that contains none.
    add_check_constraint :assessments,
                         "status = 'draft' OR (score IS NOT NULL AND reported_value IS NOT NULL)",
                         name: "assessments_published_requires_score"

    # The same XOR as training_focuses: a rubric is either a Skill or free text.
    add_check_constraint :assessments,
                         "(skill_id IS NOT NULL AND custom_skill IS NULL) OR " \
                         "(skill_id IS NULL AND custom_skill IS NOT NULL)",
                         name: "assessments_skill_xor_custom_skill"
  end
end
