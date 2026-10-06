require "test_helper"

class AccountIdentityPhase2BackfillTest < ActiveSupport::TestCase
  test "repeatable backfill links only verified people and exact creator users" do
    linked_profile = player_profiles(:john_player)
    unclaimed_profile = player_profiles(:pedro_player)
    linked_profile.update_columns(created_by_id: users(:five).id, created_by_account_id: nil)
    unclaimed_profile.update_columns(account_id: nil)
    history_before = [ Assessment.count, TrainingSessionParticipant.count, GroupMembership.count ]

    service = AccountIdentityPhase2Backfill.new
    preview = service.call(dry_run: true)
    assert_equal true, preview[:dry_run]
    assert_nil linked_profile.reload.account_id

    service.call(dry_run: false)
    linked_profile.reload
    assert_equal accounts(:one).id, linked_profile.account_id
    assert_equal accounts(:one).id, linked_profile.created_by_account_id
    assert_nil unclaimed_profile.reload.account_id

    counts_after_first_apply = service.call(dry_run: true)[:before]
    service.call(dry_run: false)
    assert_equal counts_after_first_apply, service.call(dry_run: true)[:before]
    assert_equal history_before, [ Assessment.count, TrainingSessionParticipant.count, GroupMembership.count ]
  end
end
