require "test_helper"

# Tests for TrainingSessionParticipant - the join between a TrainingSession and
# a PlayerProfile (domain identity). Accountless players can be participants.
class TrainingSessionParticipantTest < ActiveSupport::TestCase
  test "is valid with required attributes" do
    participant = training_session_participants(:session_with_participants)
    assert participant.valid?
  end

  test "requires a player_profile" do
    participant = training_session_participants(:session_with_participants)
    participant.player_profile = nil
    assert_not participant.valid?
    assert_includes participant.errors[:player_profile], "must exist"
  end

  test "requires a training_session" do
    participant = training_session_participants(:session_with_participants)
    participant.training_session = nil
    assert_not participant.valid?
    assert_includes participant.errors[:training_session], "must exist"
  end

  test "requires a valid status" do
    participant = training_session_participants(:session_with_participants)
    participant.status = "maybe"
    assert_not participant.valid?
    assert_includes participant.errors[:status], "is not included in the list"
  end

  test "accepts all defined statuses" do
    TrainingSessionParticipant::STATUSES.each do |status|
      participant = training_session_participants(:session_with_participants)
      participant.status = status
      assert participant.valid?, "expected #{status} to be valid"
    end
  end

  test "defaults to invited status" do
    participant = TrainingSessionParticipant.new(
      training_session: training_sessions(:one),
      player_profile: player_profiles(:john_player)
    )
    assert_equal "invited", participant.status
  end

  test "player and session must be unique within a session" do
    # Session two has no participants, so we can use pedro_player there.
    session = training_sessions(:two)
    player_profile = player_profiles(:pedro_player)
    TrainingSessionParticipant.create!(
      training_session: session,
      player_profile: player_profile,
      status: "invited"
    )
    duplicate = TrainingSessionParticipant.new(
      training_session: session,
      player_profile: player_profile,
      status: "invited"
    )
    assert duplicate.invalid?
    assert_includes duplicate.errors[:player_profile_id], "has already been taken"
  end

  test "prevents adding participants to a cancelled session" do
    session = training_sessions(:one)
    session.update!(status: "cancelled")
    participant = TrainingSessionParticipant.new(
      training_session: session,
      player_profile: player_profiles(:john_player)
    )
    assert_not participant.valid?
    assert_includes participant.errors[:training_session], "is cancelled"
  end

  test "player_name returns person's full_name" do
    participant = training_session_participants(:session_with_participants)
    assert_equal "John Smith", participant.player_name
  end

  test "player_name returns name even when person lacks account" do
    # accountless_participant uses pedro_player which has no account.
    participant = training_session_participants(:accountless_participant)
    assert_equal "Pedro Santos", participant.player_name
    refute participant.account_connected?
  end

  test "status_label returns capitalized status" do
    participant = training_session_participants(:session_with_participants)
    participant.update!(status: "attended")
    assert_equal "Attended", participant.status_label
  end

  test "account_connected? returns true for players with accounts" do
    participant = training_session_participants(:session_with_participants)
    assert participant.account_connected?
  end

  test "account_connected? returns false for accountless players" do
    participant = training_session_participants(:accountless_participant)
    refute participant.account_connected?
  end

  test "belongs to training_session through association" do
    participant = training_session_participants(:session_with_participants)
    assert_equal training_sessions(:one), participant.training_session
  end

  test "belongs to player_profile through association" do
    participant = training_session_participants(:session_with_participants)
    assert_equal player_profiles(:john_player), participant.player_profile
  end

  test "has_one person through player_profile" do
    participant = training_session_participants(:session_with_participants)
    assert_equal people(:one), participant.person
  end

  test "ordered scope sorts by id" do
    participants = TrainingSessionParticipant.ordered.to_a
    ids = participants.map(&:id)
    assert_equal ids.sort, ids
  end

  test "destroy removes participant but keeps session and player_profile" do
    session_id = training_sessions(:one).id
    profile_id = player_profiles(:john_player).id

    assert_difference("TrainingSessionParticipant.count", -1) do
      training_session_participants(:session_with_participants).destroy
    end

    assert TrainingSession.exists?(session_id)
    assert PlayerProfile.exists?(profile_id)
  end
end
