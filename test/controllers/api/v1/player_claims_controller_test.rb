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

  test "candidate search requires authentication" do
    get candidates_api_v1_player_claims_path

    assert_response :unauthorized
  end

  test "candidate search requires a linked active Person" do
    sign_in_as(users(:one))

    get candidates_api_v1_player_claims_path

    assert_response :unprocessable_entity
  end

  test "candidate search returns an exact unconfirmed name match with safe fields" do
    profile = PlayerProfile.create!(display_name: "John Smith", created_by: users(:three))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    assert_response :success
    candidate = JSON.parse(response.body).find { |row| row["id"] == profile.id }
    assert_equal "candidate", candidate["result_type"]
    assert_equal "exact_name", candidate["match_type"]
    assert_equal "John Smith", candidate["display_name"]
    assert_equal [ "display_name", "id", "match_type", "player_profile_id", "result_type" ], candidate.keys.sort
    assert_nil profile.reload.person_id
    assert_empty PlayerClaim.where(player_profile: profile)
  end

  test "candidate search includes partial name matches" do
    profile = PlayerProfile.create!(display_name: "John Q Smith", created_by: users(:three))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    row = JSON.parse(response.body).find { |candidate| candidate["id"] == profile.id }
    assert_equal "partial_name", row["match_type"]
  end

  test "candidate search considers a previous name alias" do
    profile = PlayerProfile.create!(display_name: "Johnny Smith", created_by: users(:three))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    row = JSON.parse(response.body).find { |candidate| candidate["id"] == profile.id }
    assert_equal "exact_name", row["match_type"]
  end

  test "candidate search returns multiple candidates and no matches as an empty array" do
    first = PlayerProfile.create!(display_name: "John Smith Jr", created_by: users(:three))
    second = PlayerProfile.create!(display_name: "Smith John", created_by: users(:three))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path
    ids = JSON.parse(response.body).map { |row| row["id"] }
    assert_includes ids, first.id
    assert_includes ids, second.id

    other = Person.create!(first_name: "Zelda", last_name: "Example")
    user = User.create!(name: "Zelda", email_address: "zelda.candidate@example.com", password: "password123")
    Account.create!(user: user, person: other)
    sign_in_as(user)
    get candidates_api_v1_player_claims_path
    assert_equal [], JSON.parse(response.body)
  end

  test "candidate search excludes profiles already claimed by any Person" do
    linked = people(:one).player_profiles.create!
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    ids = JSON.parse(response.body).map { |row| row["id"] }
    assert_not_includes ids, linked.id
    assert_not_includes ids, player_profiles(:john_player).id
  end

  test "candidate search excludes profiles with a pending claim" do
    pending_profile = PlayerProfile.create!(display_name: "John Smith", created_by: users(:three))
    PlayerClaim.create!(player_profile: pending_profile, person: people(:two),
                        initiated_by_person: people(:two), status: "pending")
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    assert_not_includes JSON.parse(response.body).map { |row| row["id"] }, pending_profile.id
  end

  test "candidate search respects private profile visibility" do
    private_profile = PlayerProfile.create!(display_name: "John Smith", visibility: "private", created_by: users(:six))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    assert_not_includes JSON.parse(response.body).map { |row| row["id"] }, private_profile.id
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
