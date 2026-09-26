# Phase 2 (Assessment Sessions), plan §2: the roster of a session.
#
# Separate from Assessment rather than reusing it as the roster, because a
# participant and a result are not the same thing: a player can be on the roster
# and still have no result (excluded, absent, or not yet scored), and a missing
# score is NEVER a silent zero (plan §16).
#
# `inclusion` distinguishes "expected to be rated" from "deliberately left out
# (injured, absent, not observed)" so consolidation can count missing coaches
# honestly instead of averaging over a denominator nobody agreed to.
class CreateAssessmentSessionParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :assessment_session_participants do |t|
      t.references :assessment_session, null: false, foreign_key: true
      t.references :player_profile, null: false, foreign_key: true

      t.string :inclusion, null: false, default: "included"
      t.string :missing_reason

      t.timestamps
    end

    add_index :assessment_session_participants,
              %i[assessment_session_id player_profile_id],
              unique: true,
              name: "index_session_participants_on_session_and_player"

    add_check_constraint :assessment_session_participants,
                         "inclusion IN ('included', 'excluded')",
                         name: "assessment_session_participants_inclusion"
  end
end