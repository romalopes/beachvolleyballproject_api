require "test_helper"

class ProfileMergeServiceTest < ActiveSupport::TestCase
  setup do
    @admin = users(:two)
  end

  test "merge archives source, keeps an audit, and moves listed history" do
    source = PlayerProfile.create!(display_name: "Duplicate Alex")
    canonical = PlayerProfile.create!(display_name: "Alex")
    participant = TrainingSessionParticipant.create!(
      training_session: training_sessions(:one), player_profile: source, status: "attended"
    )

    audit = ProfileMergeService.merge!(source: source, canonical: canonical, actor: @admin,
                                       reason: "Confirmed duplicate from club records")

    assert_equal "archived", source.reload.status
    assert_equal canonical.id, source.merged_into_profile_id
    assert_equal "active", canonical.reload.status
    assert_equal canonical.id, participant.reload.player_profile_id
    assert_equal "PlayerProfile", audit.source_profile_type
    assert_equal source.id, audit.source_profile_id
    assert_equal canonical.id, audit.canonical_profile_id
    assert_equal "Confirmed duplicate from club records", audit.reason
    assert_equal 1, audit.reference_counts.fetch("training_session_participants")
    assert_equal ProfileOwnership.account_for(@admin).id, audit.merged_by_account_id
  end

  test "rejects different profile types" do
    source = PlayerProfile.create!(display_name: "Player")
    canonical = CoachProfile.create!(display_name: "Coach")

    error = assert_raises(ProfileMergeService::Error) do
      ProfileMergeService.merge!(source: source, canonical: canonical, actor: @admin, reason: "Wrong type")
    end

    assert_match(/same type/, error.message)
    assert_equal "active", source.reload.status
    assert_empty ProfileMerge.all
  end

  test "rejects archived targets and already merged sources" do
    source = PlayerProfile.create!(display_name: "Source")
    canonical = PlayerProfile.create!(display_name: "Archived", status: "archived")

    assert_raises(ProfileMergeService::Error) do
      ProfileMergeService.merge!(source: source, canonical: canonical, actor: @admin, reason: "Bad target")
    end
    assert_equal "active", source.reload.status

    active_target = PlayerProfile.create!(display_name: "Target")
    ProfileMergeService.merge!(source: source, canonical: active_target, actor: @admin, reason: "First merge")
    assert_raises(ProfileMergeService::Error) do
      ProfileMergeService.merge!(source: source, canonical: active_target, actor: @admin, reason: "Replay")
    end
    assert_equal 1, ProfileMerge.count
  end

  test "blocks overlapping participant references without changing either record" do
    source = PlayerProfile.create!(display_name: "Source")
    canonical = PlayerProfile.create!(display_name: "Target")
    session = training_sessions(:one)
    TrainingSessionParticipant.create!(training_session: session, player_profile: source, status: "attended")
    TrainingSessionParticipant.create!(training_session: session, player_profile: canonical, status: "confirmed")

    error = assert_raises(ProfileMergeService::Error) do
      ProfileMergeService.merge!(source: source, canonical: canonical, actor: @admin, reason: "Conflict")
    end

    assert_match(/training_session_participants/, error.message)
    assert_equal "active", source.reload.status
    assert_equal "active", canonical.reload.status
    assert_equal 0, ProfileMerge.count
  end

  test "blocks profiles linked to different Accounts" do
    source = PlayerProfile.create!(display_name: "Source", account: accounts(:one))
    canonical = PlayerProfile.create!(display_name: "Target", account: accounts(:two))

    error = assert_raises(ProfileMergeService::Error) do
      ProfileMergeService.merge!(source: source, canonical: canonical, actor: @admin, reason: "Account conflict")
    end

    assert_match(/different Accounts/, error.message)
    assert_empty ProfileMerge.all
  end

  test "requires a reason and merge authorization" do
    source = PlayerProfile.create!(display_name: "Source")
    canonical = PlayerProfile.create!(display_name: "Target")

    assert_raises(ProfileMergeService::Error) do
      ProfileMergeService.merge!(source: source, canonical: canonical, actor: @admin, reason: " ")
    end
    assert_raises(ProfileMergeService::Error) do
      ProfileMergeService.merge!(source: source, canonical: canonical, actor: users(:one), reason: "No permission")
    end
    assert_equal "active", source.reload.status
    assert_empty ProfileMerge.all
  end
end
