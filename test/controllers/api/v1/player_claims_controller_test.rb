require "test_helper"

class Api::V1::PlayerClaimsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @claimant = users(:five) # linked to people(:one)
    @reviewer = users(:three) # linked coach and profile creator
    @profile = PlayerProfile.create!(display_name: "Maria Jose", created_by: users(:three))
  end

  test "claim requests require authentication" do
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }

    assert_response :unauthorized
    assert_empty PlayerClaim.all
  end

  test "a linked user can request a claim without changing profile identity" do
    sign_in_as(@claimant)
    old_id = @profile.id
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id, person_id: people(:two).id }

    assert_response :created
    claim = PlayerClaim.last
    assert_equal "pending", claim.status
    assert_equal people(:one).id, claim.person_id
    assert_equal people(:one).id, claim.initiated_by_person_id
    assert_equal old_id, claim.player_profile_id
    assert_nil @profile.reload.person_id
    assert_equal "Maria Jose", @profile.full_name
  end

  test "a personless profile cannot be claimed without a display name" do
    profile = PlayerProfile.create!(display_name: "No name")
    profile.update_column(:display_name, nil)
    sign_in_as(@claimant)

    post api_v1_player_claims_path, params: { player_profile_id: profile.id }

    assert_response :conflict
    assert_empty PlayerClaim.where(player_profile: profile)
  end

  test "only a coach or admin may approve and approval links the existing profile" do
    assessment = assessments(:draft_ready)
    assessment.update!(player_profile: @profile)
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")

    sign_in_as(@reviewer)
    post approve_api_v1_player_claim_path(claim_id)

    assert_response :success
    assert_equal "approved", PlayerClaim.find(claim_id).status
    assert_equal people(:one).id, @profile.reload.person_id
    assert_equal @profile.id, PlayerClaim.find(claim_id).player_profile_id
    assert_equal @profile.id, assessment.reload.player_profile_id
  end

  test "a claimant cannot approve their own claim" do
    sign_in_as(@reviewer)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")
    post approve_api_v1_player_claim_path(claim_id)

    assert_response :forbidden
    assert_equal "pending", PlayerClaim.find(claim_id).status
  end

  test "a different coach cannot review a profile they do not own" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")

    sign_in_as(users(:six))
    post approve_api_v1_player_claim_path(claim_id)

    assert_response :forbidden
    assert_equal "pending", PlayerClaim.find(claim_id).status
  end

  test "a second pending request for the same profile is refused" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }

    assert_response :conflict
    assert_equal 1, PlayerClaim.where(player_profile: @profile, status: "pending").count
  end

  test "rejection requires a reason and does not change the profile" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")
    sign_in_as(@reviewer)

    post reject_api_v1_player_claim_path(claim_id), params: { rejection_reason: "   " }
    assert_response :unprocessable_entity

    post reject_api_v1_player_claim_path(claim_id), params: { rejection_reason: "Please verify this record" }
    assert_response :success
    assert_equal "rejected", PlayerClaim.find(claim_id).status
    assert_nil @profile.reload.person_id
  end

  test "claimants can cancel their own pending claims but cannot cancel another person's claim" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")

    sign_in_as(@reviewer)
    post cancel_api_v1_player_claim_path(claim_id)
    assert_response :not_found

    sign_in_as(@claimant)
    post cancel_api_v1_player_claim_path(claim_id)
    assert_response :success
    assert_equal "cancelled", PlayerClaim.find(claim_id).status
    assert_nil @profile.reload.person_id
  end

  test "claimant responses do not expose the profile display name" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }

    assert_response :created
    assert_not JSON.parse(response.body).key?("player_name")
  end
end
