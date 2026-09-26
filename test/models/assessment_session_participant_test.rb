require "test_helper"

class AssessmentSessionParticipantTest < ActiveSupport::TestCase
  setup do
    @session = assessment_sessions(:draft_squad)
    @john = player_profiles(:john_player)
    @pedro = player_profiles(:pedro_player)
  end

  test "a participant belongs to a session and a player profile" do
    # Pedro is already excluded from `draft_squad`, so the valid-roster case is
    # proven against the other fixture session where he is not present.
    participant = assessment_sessions(:published_squad).participants.build(player_profile: @pedro)

    assert_predicate participant, :valid?
    assert_predicate participant, :included?, "expected players are rated"
  end

  test "inclusion is constrained to the two known states" do
    participant = @session.participants.build(player_profile: @pedro, inclusion: "maybe")

    assert_not participant.valid?
    assert participant.errors[:inclusion].any?
  end

  # The roster is a set, not a log. The same player listed twice would make
  # "how many players were rated?" ambiguous and would let a second row claim a
  # different inclusion state for a result that already exists.
  test "a player can only be rostered once per session" do
    duplicate = @session.participants.build(player_profile: @john)

    assert_not duplicate.valid?
    assert duplicate.errors[:player_profile_id].any?
  end

  test "the same player may be rostered in a different session" do
    other = assessment_sessions(:published_squad)
    participant = other.participants.build(player_profile: @pedro)

    assert_predicate participant, :valid?
  end

  test "an excluded participant records why the player is missing" do
    participant = assessment_session_participants(:draft_absent)

    assert_predicate participant, :excluded?
    assert_equal "Injured knee, not observed this session.", participant.missing_reason
  end

  test "the included scope returns only expected players" do
    included = @session.participants.included

    assert_equal [ @john.id ], included.pluck(:player_profile_id)
  end

  test "the database refuses a duplicate roster row even without validations" do
    # Fixtures are inserted with SQL, so this pins the unique index itself: a
    # model-level uniqueness check is a convenience, the index is the guarantee.
    assert_raises ActiveRecord::RecordNotUnique do
      AssessmentSessionParticipant.insert_all!([
        { assessment_session_id: @session.id, player_profile_id: @john.id,
          inclusion: "included", created_at: Time.current, updated_at: Time.current }
      ])
    end
  end
end
