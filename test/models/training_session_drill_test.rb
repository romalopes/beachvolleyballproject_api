require "test_helper"

class TrainingSessionDrillTest < ActiveSupport::TestCase
  test "accepts a valid drill link" do
    link = training_session_drills(:serve_receive_progression)
    assert link.valid?
    assert_equal drills(:one), link.drill
    assert_equal training_sessions(:one), link.training_session
    assert_equal 15, link.duration_minutes
    assert_equal "Use stronger serves for the second round.", link.notes
  end

  test "requires a drill" do
    link = TrainingSessionDrill.new(training_session: training_sessions(:one))
    assert_not link.valid?
    assert_includes link.errors.attribute_names, :drill
  end

  test "requires a training session" do
    link = TrainingSessionDrill.new(drill: drills(:one))
    assert_not link.valid?
    assert_includes link.errors.attribute_names, :training_session
  end

  test "rejects the same drill twice within one training" do
    link = TrainingSessionDrill.new(training_session: training_sessions(:one), drill: drills(:one))
    assert_not link.valid?
    assert_includes link.errors.attribute_names, :drill_id
  end

  test "allows the same drill in a different training" do
    link = TrainingSessionDrill.new(training_session: training_sessions(:three), drill: drills(:one))
    assert link.valid?
  end

  test "duration is optional but must be a positive whole number when supplied" do
    link = TrainingSessionDrill.new(training_session: training_sessions(:three), drill: drills(:one))
    assert link.valid?
    assert_nil link.duration_minutes

    link.duration_minutes = 0
    assert_not link.valid?
    assert_includes link.errors.attribute_names, :duration_minutes

    link.duration_minutes = -5
    assert_not link.valid?

    link.duration_minutes = 12.5
    assert_not link.valid?

    link.duration_minutes = 25
    assert link.valid?
  end

  test "notes are session-specific and never modify the drill" do
    link = training_session_drills(:defensive_movement)
    link.update!(notes: "Play to 21, switch sides every 7 points.")

    assert_equal "Play to 21, switch sides every 7 points.", link.reload.notes
    assert_equal drills(:two), link.drill
    assert drills(:two).reload.valid?
  end

  test "keeps the intentional position order" do
    assert_equal [ 0, 1 ], training_sessions(:one).training_session_drills.map(&:position)
    assert_equal [ training_session_drills(:serve_receive_progression).id,
                  training_session_drills(:defensive_movement).id ],
                 training_sessions(:one).training_session_drills.map(&:id)
  end

  test "duration belongs to the session, not the drill" do
    # The same drill may take different time in different trainings.
    assert_equal 15, training_session_drills(:serve_receive_progression).duration_minutes
    assert_equal 10, training_session_drills(:draft_warm_up).duration_minutes
    assert_equal drills(:one).id, training_session_drills(:draft_warm_up).drill_id
  end
end
