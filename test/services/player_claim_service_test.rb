require "test_helper"

class PlayerClaimServiceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "simultaneous approvals can link a profile to only one Account" do
    reviewer = users(:three)
    claimants = [ users(:five), users(:six) ]
    claimants.each do |user|
      OrganisationMembership.find_or_create_by!(account: user.account, organisation: organisations(:sydney_club)) do |membership|
        membership.role = "member"
        membership.status = "active"
        membership.joined_at = Time.current
      end
    end
    OrganisationMembership.find_or_create_by!(account: reviewer.account, organisation: organisations(:sydney_club)) do |membership|
      membership.role = "coach"
      membership.status = "active"
      membership.joined_at = Time.current
    end
    profile = PlayerProfile.create!(display_name: "Concurrent Claim", created_by: reviewer)
    claims = claimants.map do |user|
      PlayerClaim.create!(claimable: profile, initiated_by_account: user.account,
                          claimant_account: user.account, status: "pending")
    end

    ready = Queue.new
    start = Queue.new
    outcomes = Queue.new
    threads = claims.map do |claim|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            PlayerClaimService.approve!(claim: PlayerClaim.find(claim.id),
                                        reviewer_account: reviewer.account,
                                        verification_method: "staff_confirmed")
            outcomes << :approved
          rescue PlayerClaimService::ClaimError
            outcomes << :conflict
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)

    assert_equal [ :approved, :conflict ], 2.times.map { outcomes.pop }.sort
    assert_equal 1, claims.count { |claim| claim.reload.status == "approved" }
    assert_equal 1, claims.count { |claim| claim.reload.status == "rejected" }
    assert_includes claimants.map { |user| user.account.id }, profile.reload.account_id
  ensure
    PlayerClaim.where(claimable: profile).delete_all if profile&.persisted?
    profile&.destroy if profile&.persisted?
  end

  test "failure after linking rolls back the profile and claim decision" do
    reviewer = users(:three)
    claimant = users(:five)
    OrganisationMembership.find_or_create_by!(account: reviewer.account, organisation: organisations(:sydney_club)) do |membership|
      membership.role = "coach"
      membership.status = "active"
      membership.joined_at = Time.current
    end
    profile = PlayerProfile.create!(display_name: "Rollback Claim", created_by: reviewer)
    claim = PlayerClaim.create!(claimable: profile, initiated_by_account: claimant.account,
                                claimant_account: claimant.account,
                                status: "pending")
    subject = ClaimSubject.for(profile)
    effect = subject.method(:effect!)
    failing_effect = ->(**arguments) { effect.call(**arguments); raise "forced failure after profile link" }
    original_effect = subject.method(:effect!)
    subject.define_singleton_method(:effect!, failing_effect)

    original_for = ClaimSubject.method(:for)
    ClaimSubject.define_singleton_method(:for) { |_record| subject }
    begin
      assert_raises(RuntimeError) do
        PlayerClaimService.approve!(claim: claim, reviewer_account: reviewer.account,
                                    verification_method: "staff_confirmed")
      end
    ensure
      ClaimSubject.define_singleton_method(:for, original_for)
      subject.define_singleton_method(:effect!, original_effect)
    end

    assert_nil profile.reload.account_id
    assert_equal "pending", claim.reload.status
  ensure
    PlayerClaim.where(claimable: profile).delete_all if profile&.persisted?
    profile&.destroy if profile&.persisted?
  end

  test "approving a player profile claim transfers organisation memberships to the Account" do
    reviewer = users(:three)
    claimant = users(:five)
    organisation = Organisation.create!(name: "Claim Transfer Club")
    profile = PlayerProfile.create!(display_name: "Profile Roster Member", created_by: reviewer)
    membership = OrganisationMembership.create!(
      organisation: organisation,
      memberable: profile,
      role: "coach",
      status: "active",
      joined_at: 2.months.ago
    )
    claim = PlayerClaim.create!(claimable: profile, initiated_by_account: claimant.account,
                                claimant_account: claimant.account, status: "pending")

    PlayerClaimService.approve!(claim: claim, reviewer_account: reviewer.account,
                                verification_method: "staff_confirmed")

    transferred = organisation.organisation_memberships.find_by!(account: claimant.account)
    assert_equal "Account", transferred.memberable_type
    assert_equal claimant.account.id, transferred.memberable_id
    assert_equal membership.id, transferred.id
    assert_equal "coach", transferred.role
    assert_equal "active", transferred.status
    assert_equal claimant.account.id, profile.reload.account_id
  ensure
    PlayerClaim.where(claimable: profile).delete_all if profile&.persisted?
    OrganisationMembership.where(organisation: organisation).delete_all if organisation&.persisted?
    profile&.destroy if profile&.persisted?
    organisation&.destroy if organisation&.persisted?
  end

  test "approving a coach profile claim transfers organisation memberships to the Account" do
    reviewer = users(:three)
    claimant = users(:five)
    organisation = Organisation.create!(name: "Coach Claim Transfer Club")
    profile = CoachProfile.create!(display_name: "Profile Coach Member", created_by: reviewer)
    membership = OrganisationMembership.create!(
      organisation: organisation,
      memberable: profile,
      role: "coach",
      status: "active",
      joined_at: 2.months.ago
    )
    claim = PlayerClaim.create!(claimable: profile, initiated_by_account: claimant.account,
                                claimant_account: claimant.account, status: "pending")

    PlayerClaimService.approve!(claim: claim, reviewer_account: reviewer.account,
                                verification_method: "staff_confirmed")

    transferred = organisation.organisation_memberships.find_by!(account: claimant.account)
    assert_equal "Account", transferred.memberable_type
    assert_equal claimant.account.id, transferred.memberable_id
    assert_equal membership.id, transferred.id
    assert_equal "coach", transferred.role
    assert_equal "active", transferred.status
    assert_equal claimant.account.id, profile.reload.account_id
  ensure
    PlayerClaim.where(claimable: profile).delete_all if profile&.persisted?
    OrganisationMembership.where(organisation: organisation).delete_all if organisation&.persisted?
    profile&.destroy if profile&.persisted?
    organisation&.destroy if organisation&.persisted?
  end

  test "claim transfer merges with an existing Account membership for the same organisation" do
    reviewer = users(:three)
    claimant = users(:five)
    organisation = Organisation.create!(name: "Claim Merge Club")
    profile = PlayerProfile.create!(display_name: "Profile Merge Member", created_by: reviewer)
    old_joined_at = 4.months.ago
    profile_membership = OrganisationMembership.create!(
      organisation: organisation,
      memberable: profile,
      role: "coach",
      status: "active",
      joined_at: old_joined_at
    )
    account_membership = OrganisationMembership.create!(
      organisation: organisation,
      account: claimant.account,
      memberable: claimant.account,
      role: "member",
      status: "pending",
      joined_at: 1.month.ago
    )
    claim = PlayerClaim.create!(claimable: profile, initiated_by_account: claimant.account,
                                claimant_account: claimant.account, status: "pending")

    PlayerClaimService.approve!(claim: claim, reviewer_account: reviewer.account,
                                verification_method: "staff_confirmed")

    assert_not OrganisationMembership.exists?(profile_membership.id)
    merged = account_membership.reload
    assert_equal "Account", merged.memberable_type
    assert_equal claimant.account.id, merged.memberable_id
    assert_equal claimant.account.id, merged.account_id
    assert_equal "coach", merged.role
    assert_equal "active", merged.status
    assert_in_delta old_joined_at.to_f, merged.joined_at.to_f, 1
    assert_nil merged.left_at
  ensure
    PlayerClaim.where(claimable: profile).delete_all if profile&.persisted?
    OrganisationMembership.where(organisation: organisation).delete_all if organisation&.persisted?
    profile&.destroy if profile&.persisted?
    organisation&.destroy if organisation&.persisted?
  end
end
