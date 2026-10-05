require "test_helper"

class Api::V1::ClaimInvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = users(:three)
    @other_coach = users(:six)
    @profile = PlayerProfile.create!(display_name: "Unclaimed Player", created_by: @coach)
    @claimer = User.create!(name: "Claimer", email_address: "claimer@example.com",
                            password: "password123", email_verified_at: Time.current)
    Account.create!(user: @claimer)
  end

  test "an owner lists and creates invitations for any subject kind" do
    sign_in_as(@coach)
    post "/api/v1/claim_invitations",
         params: { claimable_type: "PlayerProfile", claimable_id: @profile.id }

    assert_response :created
    body = JSON.parse(response.body)
    invitation = ClaimInvitation.find(body.dig("invitation", "id"))
    assert_equal "PlayerProfile", invitation.claimable_type
    assert_equal @profile.id, body.dig("invitation", "player_profile_id")
    assert_not_includes response.body, invitation.token_digest

    get "/api/v1/claim_invitations",
        params: { claimable_type: "PlayerProfile", claimable_id: @profile.id }
    assert_response :success
    assert_equal invitation.id, JSON.parse(response.body).first.fetch("id")
  end

  test "redeeming a hand-copied link reports a pending review, not a link" do
    invitation, raw_token = ClaimInvitationService.issue!(
      claimable: @profile, invited_by: @coach, invitee_email: @claimer.email_address
    )
    sign_in_as(@claimer)

    post "/api/v1/claim_invitations/redeem", params: { token: raw_token }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "pending_review", body["outcome"]
    assert_nil @profile.reload.person_id
    assert body.dig("claim", "status") == "pending"
    assert_match(/review/i, body["message"])
  end

  test "redeeming an emailed invitation links immediately" do
    invitation, raw_token = ClaimInvitationService.issue!(
      claimable: @profile, invited_by: @coach, invitee_email: @claimer.email_address
    )
    ClaimInvitationService.mark_emailed!(invitation: invitation)
    sign_in_as(@claimer)

    post "/api/v1/claim_invitations/redeem", params: { token: raw_token }

    assert_response :created
    assert_equal "linked", JSON.parse(response.body)["outcome"]
    assert_equal @claimer.person.id, @profile.reload.person_id
  end

  test "issuing requires a content creator and is refused for another coach" do
    sign_in_as(@other_coach)
    post "/api/v1/claim_invitations",
         params: { claimable_type: "PlayerProfile", claimable_id: @profile.id }
    assert_response :not_found

    sign_in_as(users(:one))
    post "/api/v1/claim_invitations",
         params: { claimable_type: "PlayerProfile", claimable_id: @profile.id }
    assert_response :forbidden

    assert_empty ClaimInvitation.where(claimable_type: "PlayerProfile", claimable_id: @profile.id)
  end

  test "an unknown subject type is refused rather than guessing a class" do
    sign_in_as(@coach)

    post "/api/v1/claim_invitations",
         params: { claimable_type: "Admin::User", claimable_id: @coach.id }

    assert_response :not_found
    assert_empty ClaimInvitation.all
  end

  test "revoke kills the link for the owner" do
    invitation, = ClaimInvitationService.issue!(claimable: @profile, invited_by: @coach)
    sign_in_as(@coach)

    post "/api/v1/claim_invitations/#{invitation.id}/revoke"

    assert_response :success
    assert_equal "revoked", invitation.reload.status
  end

  test "redemption requires authentication" do
    _invitation, raw_token = ClaimInvitationService.issue!(claimable: @profile, invited_by: @coach)

    post "/api/v1/claim_invitations/redeem", params: { token: raw_token }

    assert_response :unauthorized
  end
end
