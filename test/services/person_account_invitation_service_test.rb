require "test_helper"

class PersonAccountInvitationServiceTest < ActiveSupport::TestCase
  setup do
    @person = people(:accountless_player)
    @person.update!(email: "known.person@example.com")
    @inviter = users(:two)
    @invitee = User.create!(name: "Known Person", email_address: @person.email, password: "password123",
                            email_verified_at: Time.current)
    # `User` has no after_create callback for Account, so a real signup has no
    # Account (and therefore no signup Person) until one is built on demand
    # (see Api::V1::AccountsController). Build it here to reproduce the state a
    # user is actually in by the time they redeem.
    Account.create!(user: @invitee)
  end

  test "verified invitee account attaches to the existing Person and keeps every profile id" do
    coach_profile = CoachProfile.create!(person: @person, coaching_level: "level_1")
    player_ids = @person.player_profiles.pluck(:id)
    coach_ids = @person.coach_profiles.pluck(:id)
    signup_person = @invitee.account.person
    invitation, token = PersonAccountInvitationService.issue!(person: @person, invited_by: @inviter)

    result = PersonAccountInvitationService.redeem!(raw_token: token, user: @invitee)

    assert_equal invitation.id, result.id
    assert_equal "used", invitation.reload.status
    assert_equal @invitee.id, invitation.used_by_id
    assert_equal @person.id, @invitee.reload.account.person_id
    assert_equal "merged", signup_person.reload.status
    assert_equal @person.id, signup_person.merged_into_id
    assert_equal player_ids, @person.player_profiles.pluck(:id)
    assert_equal coach_ids, @person.coach_profiles.pluck(:id)
    assert_equal coach_profile.id, @person.coach_profiles.first.id
    assert_equal "known.person@example.com", invitation.invitee_email
  end

  test "unverified email cannot attach an Account and leaves the invitation usable" do
    @invitee.update!(email_verified_at: nil)
    signup_person_id = @invitee.account.person_id
    invitation, token = PersonAccountInvitationService.issue!(person: @person, invited_by: @inviter)

    error = assert_raises(PersonAccountInvitationService::InvitationError) do
      PersonAccountInvitationService.redeem!(raw_token: token, user: @invitee)
    end

    assert_equal PersonAccountInvitationService::VERIFICATION_MESSAGE, error.message
    assert_equal signup_person_id, @invitee.reload.account.person_id
    assert_nil @person.reload.account
    assert_equal "active", invitation.reload.status
  end

  test "another email cannot use the invitation and the Person remains accountless" do
    @invitee.update!(email_address: "different@example.com")
    invitation, token = PersonAccountInvitationService.issue!(person: @person, invited_by: @inviter)

    error = assert_raises(PersonAccountInvitationService::InvitationError) do
      PersonAccountInvitationService.redeem!(raw_token: token, user: @invitee)
    end

    assert_equal PersonAccountInvitationService::INVALID_MESSAGE, error.message
    assert_nil @person.reload.account
    assert_not_nil @invitee.reload.account
    assert_equal "active", invitation.reload.status
  end

  test "an existing Account or missing Person email cannot be invited" do
    assert_raises(PersonAccountInvitationService::InvitationError) do
      PersonAccountInvitationService.issue!(person: people(:two), invited_by: @inviter)
    end

    @person.update!(email: nil)
    assert_raises(PersonAccountInvitationService::InvitationError) do
      PersonAccountInvitationService.issue!(person: @person, invited_by: @inviter)
    end
  end

  test "issuing another invitation revokes the earlier live link" do
    first, = PersonAccountInvitationService.issue!(person: @person, invited_by: @inviter)
    second, = PersonAccountInvitationService.issue!(person: @person, invited_by: @inviter)

    assert_equal "revoked", first.reload.status
    assert_equal "active", second.reload.status
  end
end
