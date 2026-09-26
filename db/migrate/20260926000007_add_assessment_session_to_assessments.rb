# Phase 2 (Assessment Sessions), plan S1: link a result to the session that
# produced it.
#
# NULLABLE on purpose. Every assessment recorded before this refactor — the whole
# Player-page workflow — belongs to no session, and the constraint is to preserve
# historical data, not to re-file it. NULL is therefore a first-class state
# ("legacy, or not yet session-scoped"), not a migration gap.
#
# ON DELETE SET NULL, matching `assessments.training_session_id`: a rating of a
# player is not undone by the schedule entry being removed, so deleting a
# session must not cascade into a destroyed history.
class AddAssessmentSessionToAssessments < ActiveRecord::Migration[8.1]
  def change
    add_reference :assessments, :assessment_session,
                  null: true,
                  foreign_key: { on_delete: :nullify }
  end
end