require "test_helper"

class TrainingSessionTest < ActiveSupport::TestCase
  test "accepts a valid training session" do
    assert training_sessions(:one).valid?
  end

  test "defaults to draft status" do
    assert_equal "draft", TrainingSession.new.status
    assert TrainingSession.new.draft?
  end

  test "requires a title" do
    session = TrainingSession.new(valid_attributes(title: nil))
    assert_not session.valid?
    assert_includes session.errors.attribute_names, :title
  end

  test "requires a start time" do
    session = TrainingSession.new(valid_attributes(starts_at: nil))
    assert_not session.valid?
    assert_includes session.errors.attribute_names, :starts_at
  end

  test "requires an end time" do
    session = TrainingSession.new(valid_attributes(ends_at: nil))
    assert_not session.valid?
    assert_includes session.errors.attribute_names, :ends_at
  end

  test "rejects an end time before the start time" do
    session = TrainingSession.new(valid_attributes(
                                    starts_at: Time.zone.parse("2026-10-01 11:00"),
                                    ends_at: Time.zone.parse("2026-10-01 09:00")
                                  ))
    assert_not session.valid?
    assert_includes session.errors.attribute_names, :ends_at
  end

  test "rejects an end time equal to the start time" do
    same = Time.zone.parse("2026-10-01 09:00")
    session = TrainingSession.new(valid_attributes(starts_at: same, ends_at: same))
    assert_not session.valid?
    assert_includes session.errors.attribute_names, :ends_at
  end

  test "accepts only known statuses" do
    TrainingSession::STATUSES.each do |status|
      session = TrainingSession.new(valid_attributes(status: status))
      assert session.valid?, "expected #{status} to be valid"
    end

    session = TrainingSession.new(valid_attributes(status: "active"))
    assert_not session.valid?
    assert_includes session.errors.attribute_names, :status
  end

  test "status predicates and labels" do
    assert training_sessions(:one).scheduled?
    assert_equal "Scheduled", training_sessions(:one).status_label
    assert training_sessions(:two).draft?
    refute training_sessions(:two).publicly_visible?
    assert training_sessions(:one).publicly_visible?

    training_sessions(:one).update!(status: "cancelled")
    assert training_sessions(:one).cancelled?
    training_sessions(:one).update!(status: "completed")
    assert training_sessions(:one).completed?
  end

  test "records the creator as an audit field" do
    assert_equal users(:three), training_sessions(:one).created_by
    assert_equal users(:four), training_sessions(:three).created_by
  end

  test "the creator is not an ownership boundary" do
    # Trainings are shared schedule resources: no `dependent` option ties the
    # session to its creator, and the association is optional so the schedule
    # outlives creator accounts.
    reflection = TrainingSession.reflect_on_association(:created_by)
    assert_nil reflection.options[:dependent]
    assert reflection.options[:optional]
  end

  test "duration_minutes reflects the calendar block" do
    assert_equal 120, training_sessions(:one).duration_minutes
    assert_nil TrainingSession.new.duration_minutes
  end

  test "ordered scope sorts by start time" do
    assert_equal [training_sessions(:one).id, training_sessions(:two).id,
                  training_sessions(:three).id], TrainingSession.ordered.pluck(:id)
  end

  test "starting_between scopes the calendar window" do
    assert_includes TrainingSession.starting_between("2026-09-21", "2026-09-22"), training_sessions(:one)
    assert_not_includes TrainingSession.starting_between("2026-09-21", "2026-09-22"), training_sessions(:three)
    assert_equal TrainingSession.count, TrainingSession.starting_between(nil, nil).count
  end

  test "visible_to hides drafts from guests and players" do
    assert_not_includes TrainingSession.visible_to(nil), training_sessions(:two)
    assert_not_includes TrainingSession.visible_to(users(:one)), training_sessions(:two)
  end

  test "visible_to shows everything to coaches, curators and admins" do
    [users(:three), users(:four), users(:two)].each do |manager|
      assert_includes TrainingSession.visible_to(manager), training_sessions(:two)
    end
  end

  test "destroys its focuses and drill links, never the referenced records" do
    session = training_sessions(:one)
    drill_ids = session.drills.pluck(:id)
    skill_ids = session.training_focuses.where.not(skill_id: nil).pluck(:skill_id)
    assert session.training_session_drills.any?

    assert_difference(["TrainingFocus.count", "TrainingSessionDrill.count"], -2) do
      session.destroy
    end

    assert_equal drill_ids, Drill.where(id: drill_ids).pluck(:id).sort
    assert_equal skill_ids, Skill.where(id: skill_ids).pluck(:id).sort
  end

  private

  def valid_attributes(overrides = {})
    {
      title: "Serve Reception Training",
      description: "Platform work.",
      starts_at: Time.zone.parse("2026-10-01 09:00"),
      ends_at: Time.zone.parse("2026-10-01 11:00"),
      location: "Coogee Beach",
      status: "scheduled",
      created_by: users(:three)
    }.merge(overrides)
  end
end
