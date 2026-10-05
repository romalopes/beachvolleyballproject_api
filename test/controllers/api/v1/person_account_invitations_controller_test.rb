require "test_helper"

class Api::V1::PersonAccountInvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @person = people(:accountless_player)
    @person.update!(email: "known.person@example.com")
    @invitee = User.create!(name: "Known Person", email_address: @person.email, password: "password123",
                            email_verified_at: Time.current)
    # See the service test: a User alone has no Account until one is built on
    # demand, so redemption must cope with both "has an account" and "has none".
    Account.create!(user: @invitee)
  end

  test "coach can issue and revoke an account invitation for a known Person" do
    sign_in_as(users(:three))
    post "/api/v1/people/#{@person.id}/account_invitations"

    assert_response :created
    body = JSON.parse(response.body)
    raw_token = body.fetch("token")
    invitation = PersonAccountInvitation.find(body.dig("invitation", "id"))
    assert_equal @person.id, invitation.person_id
    assert_equal "known.person@example.com", invitation.invitee_email
    assert_equal Digest::SHA256.hexdigest(raw_token), invitation.token_digest
    assert_not_includes invitation.attributes.values, raw_token

    get "/api/v1/people/#{@person.id}/account_invitations"
    assert_response :success
    assert_equal invitation.id, JSON.parse(response.body).first.fetch("id")
    assert_not_includes response.body, raw_token

    post "/api/v1/person_account_invitations/#{invitation.id}/revoke"
    assert_response :success
    assert_equal "revoked", invitation.reload.status
  end

  test "verified invitee redeems the link and receives the existing Person" do
    invitation, raw_token = PersonAccountInvitationService.issue!(person: @person, invited_by: users(:three))
    player_profile_id = player_profiles(:pedro_player).id
    sign_in_as(@invitee)

    post "/api/v1/person_account_invitations/redeem", params: { token: raw_token }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal invitation.id, body.dig("invitation", "id")
    assert_equal @person.id, body.dig("person", "id")
    assert_equal player_profile_id, PlayerProfile.find(player_profile_id).id
    assert_equal @person.id, PlayerProfile.find(player_profile_id).person_id
    assert_equal @person.id, @invitee.reload.account.person_id
  end

  test "mismatched email cannot redeem and does not consume the invitation" do
    invitation, raw_token = PersonAccountInvitationService.issue!(person: @person, invited_by: users(:three))
    sign_in_as(users(:five))

    post "/api/v1/person_account_invitations/redeem", params: { token: raw_token }

    assert_response :unprocessable_entity
    assert_equal PersonAccountInvitationService::INVALID_MESSAGE, JSON.parse(response.body).fetch("error")
    assert_equal "active", invitation.reload.status
    assert_nil @person.reload.account
  end

  test "invitation issue requires a content creator and does not reveal linked Person details" do
    sign_in_as(users(:one))
    post "/api/v1/people/#{@person.id}/account_invitations"
    assert_response :forbidden

    sign_in_as(users(:two))
    post "/api/v1/people/#{people(:two).id}/account_invitations"
    assert_response :conflict
    assert_empty PersonAccountInvitation.where(person: people(:two))
  end
end
