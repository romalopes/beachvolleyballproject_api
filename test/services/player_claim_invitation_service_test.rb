require "test_helper"

class PlayerClaimInvitationServiceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent redemptions consume an invitation only once" do
    profile = PlayerProfile.create!(display_name: "Concurrent Invite", created_by: users(:three))
    invitation, token = PlayerClaimInvitationService.issue!(
      player_profile: profile,
      created_by_person: people(:three_person)
    )
    ready = Queue.new
    start = Queue.new

    outcomes = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          PlayerClaimInvitationService.redeem!(raw_token: token, person: people(:one))
          :redeemed
        rescue PlayerClaimInvitationService::InvitationError
          :rejected
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    results = outcomes.map(&:value)

    assert_equal 1, results.count(:redeemed)
    assert_equal 1, results.count(:rejected)
    assert_equal "used", invitation.reload.status
    assert_equal 1, PlayerClaim.where(player_profile: profile).count
  ensure
    if profile&.persisted?
      PlayerClaim.where(player_profile: profile).delete_all
      PlayerClaimInvitation.where(player_profile: profile).delete_all
      PlayerProfile.where(id: profile.id).delete_all
    end
  end
end
