# Database-level backstops for the Training Sessions domain. Rails validations
# produce the user-facing errors; these constraints keep the data correct even
# when rows are written outside the model layer.
class AddTrainingIntegrityConstraints < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :training_sessions,
                         "ends_at > starts_at",
                         name: "training_sessions_ends_at_after_starts_at"

    add_check_constraint :training_sessions,
                         "status IN ('draft', 'scheduled', 'cancelled', 'completed')",
                         name: "training_sessions_status"

    # A focus references an existing Skill xor carries custom text.
    add_check_constraint :training_focuses,
                         "(skill_id IS NOT NULL AND custom_focus IS NULL) OR " \
                         "(skill_id IS NULL AND custom_focus IS NOT NULL)",
                         name: "training_focuses_skill_xor_custom_focus"

    add_check_constraint :training_focuses,
                         "position >= 0",
                         name: "training_focuses_position_non_negative"

    add_check_constraint :training_session_drills,
                         "position >= 0",
                         name: "training_session_drills_position_non_negative"

    add_check_constraint :training_session_drills,
                         "duration_minutes IS NULL OR duration_minutes > 0",
                         name: "training_session_drills_duration_minutes_positive"
  end

  def down
    remove_check_constraint :training_session_drills, name: "training_session_drills_duration_minutes_positive"
    remove_check_constraint :training_session_drills, name: "training_session_drills_position_non_negative"
    remove_check_constraint :training_focuses, name: "training_focuses_position_non_negative"
    remove_check_constraint :training_focuses, name: "training_focuses_skill_xor_custom_focus"
    remove_check_constraint :training_sessions, name: "training_sessions_status"
    remove_check_constraint :training_sessions, name: "training_sessions_ends_at_after_starts_at"
  end
end
