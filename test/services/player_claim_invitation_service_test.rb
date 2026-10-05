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

  # An invitation restricted to an address is only redeemable by the Person
  # holding that address. `people(:one)` is one@example.com and
  # `people(:two)` is two@example.com.
  test "an address-restricted invitation is only redeemable by that address" do
    profile = PlayerProfile.create!(display_name: "Addressed Invite", created_by: users(:three))
    _invitation, token = PlayerClaimInvitationService.issue!(
      player_profile: profile,
      created_by_person: people(:three_person),
      invitee_email: "One@Example.COM"
    )

    # Normalized on write, so the stored value is already canonical.
    assert_equal "one@example.com",
                 profile.player_claim_invitations.active.first.invitee_email

    claim = PlayerClaimInvitationService.redeem!(raw_token: token, person: people(:one))
    assert_equal people(:one).id, claim.person_id
  ensure
    if profile&.persisted?
      PlayerClaim.where(player_profile: profile).delete_all
      PlayerClaimInvitation.where(player_profile: profile).delete_all
      PlayerProfile.where(id: profile.id).delete_all
    end
  end

  test "a different address is refused and the invitation stays usable by its owner" do
    profile = PlayerProfile.create!(display_name: "Wrong Address", created_by: users(:three))
    invitation, token = PlayerClaimInvitationService.issue!(
      player_profile: profile,
      created_by_person: people(:three_person),
      invitee_email: "one@example.com"
    )

    error = assert_raises(PlayerClaimInvitationService::InvitationError) do
      PlayerClaimInvitationService.redeem!(raw_token: token, person: people(:two))
    end
    # The generic message: a wrong address must not be distinguishable from an
    # invalid token, or the endpoint becomes an address oracle.
    assert_equal PlayerClaimInvitationService::INVALID_MESSAGE, error.message
    assert_equal "active", invitation.reload.status
    assert_empty PlayerClaim.where(player_profile: profile)

    # Still redeemable by the invited address — a failed attempt must not burn it.
    PlayerClaimInvitationService.redeem!(raw_token: token, person: people(:one))
    assert_equal "used", invitation.reload.status
  ensure
    if profile&.persisted?
      PlayerClaim.where(player_profile: profile).delete_all
      PlayerClaimInvitation.where(player_profile: profile).delete_all
      PlayerProfile.where(id: profile.id).delete_all
    end
  end

  test "an invitation with no address stays an open bearer token" do
    profile = PlayerProfile.create!(display_name: "Open Invite", created_by: users(:three))
    invitation, token = PlayerClaimInvitationService.issue!(
      player_profile: profile,
      created_by_person: people(:three_person)
    )

    assert_nil invitation.invitee_email
    assert invitation.redeemable_by?(people(:two))

    claim = PlayerClaimInvitationService.redeem!(raw_token: token, person: people(:two))
    assert_equal people(:two).id, claim.person_id
  ensure
    if profile&.persisted?
      PlayerClaim.where(player_profile: profile).delete_all
      PlayerClaimInvitation.where(player_profile: profile).delete_all
      PlayerProfile.where(id: profile.id).delete_all
    end
  end

  test "a malformed invitee address is rejected" do
    profile = PlayerProfile.create!(display_name: "Bad Address", created_by: users(:three))

    assert_raises(ActiveRecord::RecordInvalid) do
      PlayerClaimInvitationService.issue!(
        player_profile: profile,
        created_by_person: people(:three_person),
        invitee_email: "not-an-email"
      )
    end
    assert_empty PlayerClaimInvitation.where(player_profile: profile)
  ensure
    if profile&.persisted?
      PlayerClaim.where(player_profile: profile).delete_all
      PlayerClaimInvitation.where(player_profile: profile).delete_all
      PlayerProfile.where(id: profile.id).delete_all
    end
  end
end
