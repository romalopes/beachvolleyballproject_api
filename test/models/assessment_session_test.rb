require "test_helper"

class AssessmentSessionTest < ActiveSupport::TestCase
  setup do
    @active = assessment_definitions(:balanced)
    @draft = assessment_definitions(:pre_season)
    @coach = coach_profiles(:maria_coach)
  end

  test "a draft session needs only an active definition and a coach" do
    session = AssessmentSession.new(
      assessment_definition: @active,
      coach_profile: @coach,
      name: "Tuesday squad screening",
      scheduled_on: Date.current
    )

    assert_predicate session, :valid?
    assert_predicate session, :draft?
  end

  test "a draft definition cannot back a session" do
    session = AssessmentSession.new(assessment_definition: @draft, coach_profile: @coach)

    assert_not session.valid?
    assert session.errors[:assessment_definition].any?
  end

  test "a coach is required" do
    session = AssessmentSession.new(assessment_definition: @active)

    assert_not session.valid?
    assert session.errors[:coach_profile].any?
  end

  test "status is constrained to the lifecycle" do
    session = AssessmentSession.new(
      assessment_definition: @active, coach_profile: @coach, status: "archived"
    )

    assert_not session.valid?
    assert session.errors[:status].any?
  end

  # A published session is archival. Without published_at it is not "published
  # yet", it is a row that lies about its own state, so the model refuses it
  # rather than letting the API hand out a session nobody can date.
  test "publishing requires a published_at timestamp" do
    session = AssessmentSession.new(
      assessment_definition: @active, coach_profile: @coach, status: "published"
    )

    assert_not session.valid?
    assert session.errors[:published_at].any?
  end

  test "the definition only has to be active when the session is created" do
    # Archiving a definition must not invalidate the sessions that already quote
    # it — otherwise retiring a template would silently orphan the history that
    # depends on it.
    session = assessment_sessions(:published_squad)
    @active.update!(status: "archived")

    assert session.valid?
  end

  test "included_participants separates expected players from absentees" do
    session = assessment_sessions(:draft_squad)

    ids = session.included_participants.pluck(:player_profile_id)
    assert_equal [ player_profiles(:john_player).id ], ids
    assert_equal 2, session.participants.count
  end

  test "destroying a session destroys its roster" do
    session = assessment_sessions(:draft_squad)
    participant_ids = session.participants.pluck(:id)

    session.destroy!

    assert_empty AssessmentSessionParticipant.where(id: participant_ids)
  end

  test "a session deletion never destroys the results that quote it" do
    session = assessment_sessions(:published_squad)
    player = player_profiles(:john_player)

    assessment = Assessment.new(
      player_profile: player,
      coach_profile: @coach,
      assessment_definition: @active,
      assessment_session: session,
      status: "draft"
    )
    @active.assessment_categories.ordered.each do |category|
      assessment.assessment_category_scores.build(
        assessment_category: category,
        scale: "one_to_ten",
        reported_value: 8,
        score: 80
      )
    end
    assessment.save!
    assessment.update!(status: "active")

    session.destroy!

    assert_nil assessment.reload.assessment_session_id, "the historical result must survive"
    assert_predicate assessment, :persisted?
  end
end
