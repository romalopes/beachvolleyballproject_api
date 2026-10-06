require "test_helper"

class Api::V1::PlayerClaimsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @claimant = users(:five) # linked to people(:one)
    @reviewer = users(:three) # linked coach and profile creator
    # Claim discovery is scoped to the claimant's active organisation and to
    # profiles recorded by someone in that same organisation.
    OrganisationMembership.find_or_create_by!(
      person: @reviewer.person, organisation: organisations(:sydney_club)
    ) do |membership|
      membership.role = "coach"
      membership.status = "active"
      membership.joined_at = Time.current
    end
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

  test "candidate search requires an Account with an active identity" do
    sign_in_as(users(:one))

    get candidates_api_v1_player_claims_path

    assert_response :unprocessable_entity
  end

  test "candidate search returns an exact unconfirmed name match with safe fields" do
    profile = PlayerProfile.create!(display_name: "John Smith", created_by: users(:three))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    assert_response :success
    candidate = JSON.parse(response.body).fetch("data").find { |row| row["id"] == profile.id }
    assert_equal "candidate", candidate["result_type"]
    assert_equal "exact_name", candidate["match_type"]
    assert_equal "John Smith", candidate["display_name"]
    assert_equal [ "claimable_id", "claimable_type", "display_name", "id", "match_type", "player_profile_id", "result_type" ], candidate.keys.sort
    assert_nil profile.reload.person_id
    assert_empty PlayerClaim.where(claimable_type: "PlayerProfile", claimable_id: profile.id)
  end

  test "candidate search includes partial name matches" do
    profile = PlayerProfile.create!(display_name: "John Q Smith", created_by: users(:three))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    row = JSON.parse(response.body).fetch("data").find { |candidate| candidate["id"] == profile.id }
    assert_equal "partial_name", row["match_type"]
  end

  test "candidate search considers a previous name alias" do
    profile = PlayerProfile.create!(display_name: "Johnny Smith", created_by: users(:three))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    row = JSON.parse(response.body).fetch("data").find { |candidate| candidate["id"] == profile.id }
    assert_equal "exact_name", row["match_type"]
  end

  test "candidate search returns multiple candidates and no matches as an empty array" do
    first = PlayerProfile.create!(display_name: "John Smith Jr", created_by: users(:three))
    second = PlayerProfile.create!(display_name: "Smith John", created_by: users(:three))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path
    ids = JSON.parse(response.body).fetch("data").map { |row| row["id"] }
    assert_includes ids, first.id
    assert_includes ids, second.id

    other = Person.create!(first_name: "Zelda", last_name: "Example")
    user = User.create!(name: "Zelda", email_address: "zelda.candidate@example.com", password: "password123")
    Account.create!(user: user, person: other)
    sign_in_as(user)
    get candidates_api_v1_player_claims_path
    assert_empty JSON.parse(response.body).fetch("data")
  end

  test "candidate search excludes profiles already claimed by any Person" do
    linked = people(:one).player_profiles.create!
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    ids = JSON.parse(response.body).fetch("data").map { |row| row["id"] }
    assert_not_includes ids, linked.id
    assert_not_includes ids, player_profiles(:john_player).id
  end

  test "candidate search permits competing claim requests" do
    pending_profile = PlayerProfile.create!(display_name: "John Smith", created_by: users(:three))
    PlayerClaim.create!(player_profile: pending_profile, person: people(:two),
                        initiated_by_person: people(:two), status: "pending")
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    assert_includes JSON.parse(response.body).fetch("data").map { |row| row["id"] }, pending_profile.id
  end

  test "candidate search includes an accountless profile already linked to a Person" do
    person = Person.create!(first_name: "John", last_name: "Smith", creation_source: "coach_created")
    linked_profile = PlayerProfile.create!(person: person, created_by: users(:three))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    assert_response :success
    assert_includes JSON.parse(response.body).fetch("data").map { |row| row["id"] }, linked_profile.id
  end

  test "candidate results support pagination" do
    PlayerProfile.create!(display_name: "John Smith Alpha", created_by: users(:three))
    PlayerProfile.create!(display_name: "John Smith Beta", created_by: users(:three))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path, params: { page: 2, per_page: 1 }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 2, body.dig("meta", "page")
    assert_equal 2, body.dig("meta", "total")
    assert_equal 1, body.fetch("data").length
  end

  test "candidate search respects private profile visibility" do
    private_profile = PlayerProfile.create!(display_name: "John Smith", visibility: "private", created_by: users(:six))
    sign_in_as(@claimant)

    get candidates_api_v1_player_claims_path

    assert_not_includes JSON.parse(response.body).fetch("data").map { |row| row["id"] }, private_profile.id
  end

  test "administrators do not get global claim discovery without an organisation or coaching relationship" do
    profile = PlayerProfile.create!(display_name: "John Smith", created_by: users(:three))
    person = Person.create!(first_name: "Unrelated", last_name: "Administrator", creation_source: "system")
    admin = User.create!(name: "Unrelated Administrator", email_address: "unrelated.admin@example.com", password: "password123")
    admin.add_role(:admin)
    Account.create!(user: admin, person: person)
    sign_in_as(admin)

    get candidates_api_v1_player_claims_path

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("data")
    assert_nil profile.reload.account_id
  end

  test "an Account outside the profile organization cannot discover it" do
    profile = PlayerProfile.create!(display_name: "John Smith", created_by: users(:three))
    unrelated = User.create!(name: "Unrelated Player", email_address: "unrelated.player@example.com", password: "password123")
    unrelated_person = Person.create!(first_name: "John", last_name: "Smith", creation_source: "signup")
    Account.create!(user: unrelated, person: unrelated_person)
    sign_in_as(unrelated)

    get candidates_api_v1_player_claims_path

    assert_response :success
    assert_empty JSON.parse(response.body).fetch("data")
    assert_nil profile.reload.account_id
  end

  test "a linked user can request a claim without changing profile identity" do
    sign_in_as(@claimant)
    old_id = @profile.id
    post api_v1_player_claims_path, params: {
      player_profile_id: @profile.id,
      person_id: people(:two).id,
      claimant_account_id: users(:six).account.id
    }

    assert_response :created
    claim = PlayerClaim.last
    assert_equal "pending", claim.status
    assert_equal people(:one).id, claim.person_id
    assert_equal @claimant.account.id, claim.claimant_account_id
    assert_equal people(:one).id, claim.initiated_by_person_id
    assert_equal old_id, claim.player_profile_key
    assert_nil @profile.reload.person_id
    assert_equal "Maria Jose", @profile.full_name
  end

  test "a coach can see their own claim status alongside their review queue" do
    sign_in_as(@reviewer)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")

    get api_v1_player_claims_path

    assert_response :success
    claim = JSON.parse(response.body).fetch("data").find { |row| row["id"] == claim_id }
    assert_equal "pending", claim.fetch("status")
  end

  test "a personless profile without a display name is not claimable" do
    profile = PlayerProfile.create!(display_name: "No name")
    profile.update_column(:display_name, nil)
    sign_in_as(@claimant)

    post api_v1_player_claims_path, params: { player_profile_id: profile.id }

    assert_response :not_found
    assert_empty PlayerClaim.where(claimable_type: "PlayerProfile", claimable_id: profile.id)
  end

  test "only a coach or admin may approve and approval links the existing profile" do
    assessment = assessments(:draft_ready)
    assessment.update!(player_profile: @profile)
    @profile.update!(visibility: "private", created_by: @claimant)
    reviewer_person = Person.create!(first_name: "Admin", last_name: "Reviewer", creation_source: "system")
    Account.create!(user: users(:two), person: reviewer_person)
    assessment_before_claim = assessment.reload.attributes.slice(
      "id", "player_profile_id", "coach_profile_id", "score", "reported_value",
      "scale", "status", "created_at", "updated_at", "notes"
    )
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")

    sign_in_as(users(:two)) # admin with a linked Person may review a private profile
    post approve_api_v1_player_claim_path(claim_id), params: { verification_method: "staff_confirmed" }

    assert_response :success
    assert_equal "approved", PlayerClaim.find(claim_id).status
    assert_equal people(:one).id, @profile.reload.person_id
    assert_equal @claimant.account.id, @profile.reload.account_id
    assert_equal users(:two).account.id, PlayerClaim.find(claim_id).reviewed_by_account_id
    assert_equal "staff_confirmed", PlayerClaim.find(claim_id).verification_method
    assert_equal "private", @profile.visibility
    assert_equal @profile.id, PlayerClaim.find(claim_id).player_profile_key
    assert_equal assessment_before_claim, assessment.reload.attributes.slice(*assessment_before_claim.keys)
  end

  test "a claimant cannot approve their own claim" do
    sign_in_as(@reviewer)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")
    post approve_api_v1_player_claim_path(claim_id), params: { verification_method: "staff_confirmed" }

    assert_response :forbidden
    assert_equal "pending", PlayerClaim.find(claim_id).status
  end

  test "approval requires a valid verification method and leaves a pending claim unchanged" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")
    sign_in_as(@reviewer)

    post approve_api_v1_player_claim_path(claim_id), params: { verification_method: "" }

    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body).fetch("code")
    assert_equal "pending", PlayerClaim.find(claim_id).status
    assert_nil @profile.reload.account_id
  end

  test "approval conflicts when the profile was linked after the request was submitted" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")
    competing_account = users(:six).account
    @profile.update!(account: competing_account)
    sign_in_as(@reviewer)

    post approve_api_v1_player_claim_path(claim_id), params: { verification_method: "staff_confirmed" }

    assert_response :conflict
    assert_equal "conflict", JSON.parse(response.body).fetch("code")
    assert_equal competing_account.id, @profile.reload.account_id
    assert_equal "pending", PlayerClaim.find(claim_id).status
  end

  test "a different coach cannot review a profile they do not own" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")

    sign_in_as(users(:six))
    post approve_api_v1_player_claim_path(claim_id), params: { verification_method: "staff_confirmed" }

    assert_response :forbidden
    assert_equal "pending", PlayerClaim.find(claim_id).status
  end

  test "a second pending request by the same Account is refused" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }

    assert_response :conflict
    assert_equal 1, PlayerClaim.where(claimable_type: "PlayerProfile", claimable_id: @profile.id, status: "pending").count
  end

  test "different Accounts may submit competing pending requests for the profile" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    first_claim = PlayerClaim.last

    second_person = people(:two)
    OrganisationMembership.find_or_create_by!(
      person: second_person, organisation: organisations(:sydney_club)
    ) do |membership|
      membership.role = "member"
      membership.status = "active"
      membership.joined_at = Time.current
    end
    sign_in_as(users(:six))
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }

    assert_response :created
    second_claim = PlayerClaim.last
    assert_equal "pending", first_claim.status
    assert_equal "pending", second_claim.status
    assert_not_equal first_claim.claimant_account_id, second_claim.claimant_account_id

    sign_in_as(@reviewer)
    post approve_api_v1_player_claim_path(first_claim.id), params: { verification_method: "in_person" }

    assert_response :success
    assert_equal "approved", first_claim.reload.status
    assert_equal "rejected", second_claim.reload.status
    assert_equal users(:three).account.id, second_claim.reviewed_by_account_id
    assert_equal "Another claim for this profile was approved", second_claim.rejection_reason
    assert_equal first_claim.claimant_account_id, @profile.reload.account_id
  end

  test "claim index returns a paginated account-scoped result" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    get api_v1_player_claims_path, params: { page: 1, per_page: 1 }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.dig("meta", "total")
    assert_equal 1, body.fetch("data").length
    claim = PlayerClaim.find(body.fetch("data").first.fetch("id"))
    assert_equal @claimant.account.id, claim.claimant_account_id
  end

  test "rejection reason is optional and rejection does not change the profile" do
    sign_in_as(@claimant)
    post api_v1_player_claims_path, params: { player_profile_id: @profile.id }
    claim_id = JSON.parse(response.body).fetch("id")
    sign_in_as(@reviewer)

    post reject_api_v1_player_claim_path(claim_id)
    assert_response :success
    assert_equal "rejected", PlayerClaim.find(claim_id).status
    assert_nil PlayerClaim.find(claim_id).rejection_reason
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
