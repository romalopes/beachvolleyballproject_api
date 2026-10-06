require "test_helper"

class ClaimInvitationTest < ActiveSupport::TestCase
  test "normalizes recipient email and never returns the token digest in its summary" do
    invitation, raw_token = ClaimInvitationService.issue!(
      claimable: PlayerProfile.create!(display_name: "Invitation Model", created_by: users(:three)),
      invited_by: users(:three),
      invitee_email: "  New.Person@Example.COM  "
    )

    assert_equal "new.person@example.com", invitation.invitee_email
    assert_equal Digest::SHA256.hexdigest(raw_token), invitation.token_digest
    assert_not_includes invitation.summary.keys, :token_digest
    assert_not_includes invitation.summary.values, raw_token
  end

  test "an active invitation reports expired when its deadline passes" do
    invitation, = ClaimInvitationService.issue!(
      claimable: PlayerProfile.create!(display_name: "Expired Invitation", created_by: users(:three)),
      invited_by: users(:three)
    )
    invitation.update_column(:expires_at, 1.minute.ago)

    assert_equal "expired", invitation.summary.fetch(:status)
    assert_equal "active", invitation.reload.status, "effective expiration does not rewrite history until a redemption attempt"
  end
end
