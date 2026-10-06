require "test_helper"

class PlayerClaimTest < ActiveSupport::TestCase
  # The Phase 18 migration clears `player_profile_id`, so the review queue and
  # approval path must work off the polymorphic subject. A freshly created claim
  # already stores the subject polymorphically, which is exactly the shape a
  # migrated row has — these guard the code paths a backfill leaves behind.
  test "a claim stored polymorphically is still visible to its reviewer and approvable" do
    OrganisationMembership.find_or_create_by!(person: people(:three_person), organisation: organisations(:sydney_club)) do |membership|
      membership.role = "coach"
      membership.status = "active"
      membership.joined_at = Time.current
    end
    profile = PlayerProfile.create!(display_name: "Migrated Shape", created_by: users(:three))
    claim = PlayerClaim.create!(claimable: profile, person: people(:one),
                                initiated_by_person: people(:one), status: "pending")

    assert_nil claim.player_profile_id, "the legacy column stays clear"
    assert_equal profile.id, claim.player_profile_key, "but the API key is preserved"
    assert_equal profile, claim.subject
    assert claim.reviewable_by?(users(:three))
    assert_not claim.reviewable_by?(users(:six))
    assert_includes PlayerClaim.pending_for_owner(users(:three)), claim

    PlayerClaimService.approve!(claim: claim, reviewer: people(:three_person), verification_method: "staff_confirmed")
    assert_equal "approved", claim.reload.status
    assert_equal people(:one).id, profile.reload.person_id
    assert_equal people(:one).account.id, profile.reload.account_id
    assert_equal users(:three).account.id, claim.reviewed_by_account_id
    assert_equal "staff_confirmed", claim.verification_method
  end

  test "pending_for_owner covers a coach profile subject as well as a player one" do
    coach = CoachProfile.create!(display_name: "Unclaimed Coach", created_by: users(:three))
    claim = PlayerClaim.create!(claimable: coach, person: people(:one),
                                initiated_by_person: people(:one), status: "pending")

    assert_includes PlayerClaim.pending_for_owner(users(:three)), claim
    assert_empty PlayerClaim.pending_for_owner(users(:six))
  end
end
