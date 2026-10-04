require "test_helper"

class Api::V1::PlayerClaimInvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:three)
    @other_coach = users(:six)
    @claimant = users(:five)
    @profile = PlayerProfile.create!(display_name: "Maria Jose", created_by: @owner)
  end

  test "authorized profile owner creates a single-use invitation with only a digest stored" do
    sign_in_as(@owner)

    assert_no_difference("Person.count") do
      post api_v1_player_claim_invitations_path, params: { player_profile_id: @profile.id }
    end

    assert_response :created
    body = JSON.parse(response.body)
    raw_token = body.fetch("token")
    invitation = PlayerClaimInvitation.find(body.dig("invitation", "id"))
    assert_equal Digest::SHA256.hexdigest(raw_token), invitation.token_digest
    assert_not_includes invitation.attributes.values, raw_token
    assert_operator invitation.expires_at, :>, Time.current
    assert_nil invitation.used_at
    assert_equal "active", invitation.status
    assert_nil @profile.reload.person_id
  end

  test "user redeems a valid invitation into a pending claim without linking or creating a Person" do
    raw_token, invitation = create_invitation
    sign_in_as(@claimant)

    assert_no_difference("Person.count") do
      post redeem_api_v1_player_claim_invitations_path, params: { token: raw_token }
    end

    assert_response :created
    claim = PlayerClaim.find(JSON.parse(response.body).dig("claim", "id"))
    assert_equal people(:one).id, claim.person_id
    assert_equal people(:three_person).id, claim.initiated_by_person_id
    assert_equal "pending", claim.status
    assert_nil @profile.reload.person_id
    assert_equal "used", invitation.reload.status
    assert_equal people(:one).id, invitation.used_by_person_id
    assert invitation.used_at
  end

  test "expired invitations cannot be redeemed and are marked expired" do
    raw_token, invitation = create_invitation
    invitation.update!(expires_at: 1.hour.ago)
    sign_in_as(@claimant)

    post redeem_api_v1_player_claim_invitations_path, params: { token: raw_token }

    assert_response :unprocessable_entity
    assert_equal PlayerClaimInvitationService::INVALID_MESSAGE, JSON.parse(response.body)["error"]
    assert_equal "expired", invitation.reload.status
    assert_empty PlayerClaim.where(player_profile: @profile)
  end

  test "revoked invitations cannot be redeemed" do
    raw_token, invitation = create_invitation
    sign_in_as(@owner)
    post revoke_api_v1_player_claim_invitation_path(invitation.id)
    assert_response :success
    assert_equal "revoked", invitation.reload.status

    sign_in_as(@claimant)
    post redeem_api_v1_player_claim_invitations_path, params: { token: raw_token }

    assert_response :unprocessable_entity
    assert_empty PlayerClaim.where(player_profile: @profile)
  end

  test "used invitations cannot be replayed" do
    raw_token, invitation = create_invitation
    sign_in_as(@claimant)
    post redeem_api_v1_player_claim_invitations_path, params: { token: raw_token }
    assert_response :created

    post redeem_api_v1_player_claim_invitations_path, params: { token: raw_token }

    assert_response :unprocessable_entity
    assert_equal "used", invitation.reload.status
    assert_equal 1, PlayerClaim.where(player_profile: @profile).count
  end

  test "invalid tokens receive the same generic response as expired and revoked invitations" do
    sign_in_as(@claimant)

    post redeem_api_v1_player_claim_invitations_path, params: { token: "not-a-real-token" }

    assert_response :unprocessable_entity
    assert_equal PlayerClaimInvitationService::INVALID_MESSAGE, JSON.parse(response.body)["error"]
  end

  test "invitation generation is restricted to the profile creator or an admin" do
    sign_in_as(@other_coach)
    post api_v1_player_claim_invitations_path, params: { player_profile_id: @profile.id }
    assert_response :not_found

    sign_in_as(@claimant)
    post api_v1_player_claim_invitations_path, params: { player_profile_id: @profile.id }
    assert_response :forbidden

    assert_empty PlayerClaimInvitation.where(player_profile: @profile)
  end

  test "redemption requires authentication" do
    raw_token, = create_invitation
    sign_out

    post redeem_api_v1_player_claim_invitations_path, params: { token: raw_token }

    assert_response :unauthorized
    assert_equal "active", PlayerClaimInvitation.last.status
  end

  test "an invitation cannot be redeemed once its profile is already claimed" do
    raw_token, invitation = create_invitation
    @profile.update!(person: people(:two))
    sign_in_as(@claimant)

    post redeem_api_v1_player_claim_invitations_path, params: { token: raw_token }

    assert_response :unprocessable_entity
    assert_equal people(:two).id, @profile.reload.person_id
    assert_equal "active", invitation.reload.status
    assert_empty PlayerClaim.where(player_profile: @profile)
  end

  test "raw invitation tokens are omitted from management responses and audit logs" do
    raw_token, invitation = create_invitation
    sign_in_as(@owner)

    get api_v1_player_claim_invitations_path, params: { player_profile_id: @profile.id }

    assert_response :success
    body = response.body
    assert_not_includes body, raw_token
    assert_not_includes body, invitation.token_digest
    assert_not Log.where(path: request.path).any? { |log| log.description.include?(raw_token) }
  end

  test "invitation status can be retrieved by its owner without exposing token material" do
    raw_token, invitation = create_invitation
    sign_in_as(@owner)

    get api_v1_player_claim_invitation_path(invitation)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal invitation.id, body["id"]
    assert_equal "active", body["status"]
    assert_not_includes response.body, raw_token
    assert_not_includes response.body, invitation.token_digest
  end

  test "invitation status is concealed from unrelated coaches" do
    _raw_token, invitation = create_invitation
    sign_in_as(@other_coach)

    get api_v1_player_claim_invitation_path(invitation)

    assert_response :not_found
    assert_not_includes response.body, invitation.token_digest
  end

  private

  def create_invitation
    sign_in_as(@owner)
    post api_v1_player_claim_invitations_path, params: { player_profile_id: @profile.id }
    assert_response :created
    body = JSON.parse(response.body)
    [ body.fetch("token"), PlayerClaimInvitation.find(body.dig("invitation", "id")) ]
  end
end
