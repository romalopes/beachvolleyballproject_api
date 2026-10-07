require "test_helper"

class ClaimInvitationConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "a one-time profile invitation can be redeemed by only one Account concurrently" do
    inviter = users(:three)
    recipients = [ users(:five), users(:six) ]
    profile = PlayerProfile.create!(display_name: "One Time Invite", created_by: inviter)
    invitation, token = ClaimInvitationService.issue!(claimable: profile, invited_by: inviter)

    ready = Queue.new
    start = Queue.new
    outcomes = Queue.new
    threads = recipients.map do |recipient|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            ClaimInvitationService.redeem!(raw_token: token, user: User.find(recipient.id))
            outcomes << :redeemed
          rescue ClaimInvitationService::InvitationError
            outcomes << :rejected
          end
        end
      end
    end
    recipients.length.times { ready.pop }
    recipients.length.times { start << true }
    threads.each(&:join)

    assert_equal [ :redeemed, :rejected ], recipients.length.times.map { outcomes.pop }.sort
    assert_equal "used", invitation.reload.status
    assert_includes recipients.map { |recipient| recipient.account.id }, profile.reload.account_id
  ensure
    PlayerClaim.where(claimable: profile).delete_all if profile&.persisted?
    ClaimInvitation.where(claimable: profile).delete_all if profile&.persisted?
    profile&.destroy if profile&.persisted?
  end
end
