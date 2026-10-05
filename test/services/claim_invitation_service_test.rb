require "test_helper"

# The auto-approve gate is the security-critical rule of the unified workflow:
# an invitation links an identity immediately ONLY when the club actually emailed
# it to the address the recipient controls. Everything else goes to staff review.
class ClaimInvitationServiceTest < ActiveSupport::TestCase
  setup do
    @coach = users(:three)
    @subject = PlayerProfile.create!(display_name: "Unclaimed Player", created_by: @coach)
    @claimer = User.create!(name: "Claimer", email_address: "claimer@example.com",
                            password: "password123", email_verified_at: Time.current)
    Account.create!(user: @claimer)
  end

  def issue(**kwargs)
    ClaimInvitationService.issue!(claimable: @subject, invited_by: @coach, **kwargs)
  end

  def email_it(invitation, token)
    ClaimInvitationDelivery.deliver(invitation: invitation, raw_token: token)
    ClaimInvitationService.mark_emailed!(invitation: invitation)
  end

  def accountless_person(email)
    Person.create!(first_name: "Known", last_name: "Person", status: "active",
                   creation_source: "coach_created", created_by: @coach, email: email)
  end

  test "an emailed invitation auto-links the profile to the claimant" do
    invitation, token = issue(invitee_email: @claimer.email_address)
    email_it(invitation, token)

    result = ClaimInvitationService.redeem!(raw_token: token, user: @claimer)

    assert_equal :linked, result[:outcome]
    assert_equal @claimer.person.id, @subject.reload.person_id
    assert_equal "used", invitation.reload.status
    assert_empty PlayerClaim.pending.where(claimable_type: "PlayerProfile", claimable_id: @subject.id)
  end

  test "a hand-copied link with the same verified address links immediately" do
    # Email delivery is telemetry; the exact verified account address is proof.
    _invitation, token = issue(invitee_email: @claimer.email_address)

    result = ClaimInvitationService.redeem!(raw_token: token, user: @claimer)

    assert_equal :linked, result[:outcome]
    assert_equal @claimer.person.id, @subject.reload.person_id
    assert_equal "used", result[:invitation].status
  end

  test "an invitation with no address can never auto-approve" do
    _invitation, token = issue

    result = ClaimInvitationService.redeem!(raw_token: token, user: @claimer)

    assert_equal :pending_review, result[:outcome]
    assert_nil @subject.reload.person_id
  end

  test "an unverified address cannot redeem an address-restricted invitation" do
    invitation, token = issue(invitee_email: @claimer.email_address)
    @claimer.update!(email_verified_at: nil)

    error = assert_raises(ClaimInvitationService::InvitationError) do
      ClaimInvitationService.redeem!(raw_token: token, user: @claimer)
    end
    assert_equal ClaimInvitationService::VERIFICATION_MESSAGE, error.message
    assert_nil @subject.reload.person_id, "an unverified account must not auto-link"
    assert_equal "active", invitation.reload.status
    assert_empty PlayerClaim.pending.where(claimable: @subject)
  end

  test "a different address is refused with the generic message" do
    _invitation, token = issue(invitee_email: "someone.else@example.com")

    error = assert_raises(ClaimInvitationService::InvitationError) do
      ClaimInvitationService.redeem!(raw_token: token, user: @claimer)
    end

    # Identical to an invalid token: the endpoint must never confirm that a
    # given address was invited.
    assert_equal ClaimInvitationService::INVALID_MESSAGE, error.message
    assert_nil @subject.reload.person_id
  end
  test "one pending claim per subject even when a second person tries" do
    other = User.create!(name: "Second", email_address: "second@example.com",
                         password: "password123", email_verified_at: Time.current)
    Account.create!(user: other)
    _invitation, token = issue
    ClaimInvitationService.redeem!(raw_token: token, user: @claimer)

    _second, second_token = issue
    assert_raises(ClaimInvitationService::InvitationError) do
      ClaimInvitationService.redeem!(raw_token: second_token, user: other)
    end
  end

  test "issuing another invitation revokes the earlier live link" do
    first, = issue
    second, = issue

    assert_equal "revoked", first.reload.status
    assert_equal "active", second.reload.status
  end

  test "an eligible coach profile is claimable just like a player profile" do
    coach = CoachProfile.create!(display_name: "Unclaimed Coach", created_by: @coach)
    invitation, token = ClaimInvitationService.issue!(claimable: coach, invited_by: @coach)

    result = ClaimInvitationService.redeem!(raw_token: token, user: @claimer)

    assert_equal :pending_review, result[:outcome]
    assert_equal "CoachProfile", invitation.claimable_type
    assert_equal coach.id, invitation.claimable_id
  end

  test "a coach profile with a Person is not eligible" do
    coach = CoachProfile.create!(person: people(:two), created_by: @coach)

    error = assert_raises(ClaimInvitationService::InvitationError) do
      ClaimInvitationService.issue!(claimable: coach, invited_by: @coach)
    end

    assert_match(/active and unlinked/i, error.message)
  end

  test "a person subject auto-links the account when emailed" do
    person = accountless_person(@claimer.email_address)
    invitation, token = ClaimInvitationService.issue!(claimable: person, invited_by: @coach)
    email_it(invitation, token)

    result = ClaimInvitationService.redeem!(raw_token: token, user: @claimer)

    assert_equal :linked, result[:outcome]
    assert_equal person.id, @claimer.reload.account.person_id
  end

  test "a person subject links after exact verified email even without email delivery" do
    person = accountless_person(@claimer.email_address)
    _invitation, token = ClaimInvitationService.issue!(claimable: person, invited_by: @coach)
    placeholder_id = @claimer.account.person_id

    result = ClaimInvitationService.redeem!(raw_token: token, user: @claimer)

    assert_equal :linked, result[:outcome]
    assert_not_equal placeholder_id, @claimer.reload.account.person_id
    assert_equal person.id, @claimer.account.person_id
    assert_equal @claimer.id, person.reload.account.user_id
  end

  test "a person with an existing account or no email cannot be invited" do
    person = accountless_person(nil)
    error = assert_raises(ClaimInvitationService::InvitationError) do
      ClaimInvitationService.issue!(claimable: person, invited_by: @coach)
    end
    assert_match(/valid email address/i, error.message)

    linked = people(:one)
    assert linked.account, "fixture must have an account for this to mean anything"
    assert_raises(ClaimInvitationService::InvitationError) do
      ClaimInvitationService.issue!(claimable: linked, invited_by: @coach)
    end
  end

  test "expired and unknown tokens are refused the same way" do
    invitation, token = issue
    invitation.update!(expires_at: 1.hour.ago)
    expired = assert_raises(ClaimInvitationService::InvitationError) do
      ClaimInvitationService.redeem!(raw_token: token, user: @claimer)
    end
    assert_equal ClaimInvitationService::INVALID_MESSAGE, expired.message
    assert_equal "expired", invitation.reload.status

    unknown = assert_raises(ClaimInvitationService::InvitationError) do
      ClaimInvitationService.redeem!(raw_token: "not-a-real-token", user: @claimer)
    end
    assert_equal ClaimInvitationService::INVALID_MESSAGE, unknown.message
  end
end
