require "test_helper"

class IdentityProductionReadinessReportTest < ActiveSupport::TestCase
  test "report emits aggregate readiness and preservation checks without changing row counts" do
    before_counts = [ Account.count, PlayerProfile.count, CoachProfile.count ]
    report = IdentityProductionReadinessReport.new.call
    after_counts = [ Account.count, PlayerProfile.count, CoachProfile.count ]

    assert_equal true, report[:read_only]
    assert_equal before_counts, after_counts
    assert_equal Rails.env, report[:environment]
    assert_equal IdentityProductionReadinessReport::REQUIRED_MIGRATIONS.to_h { |version| [ version, true ] },
                 report[:required_identity_migrations]
    assert_equal 0, report[:blockers]
    assert_equal 0, report[:orphan_counts].values.sum
    assert_includes report[:preservation_counts].keys, :assessments
    assert_includes report[:preservation_counts].keys, :group_memberships
    assert_includes report[:preservation_counts].keys, :contact_details
    assert report.key?(:cardinality)
    assert report.key?(:anomalies)
  end

  test "reports an Account without its required ContactDetail as a blocker" do
    account = accounts(:one)
    ContactDetail.where(account_id: account.id).delete_all

    report = IdentityProductionReadinessReport.new.call

    finding = report[:anomalies].find { |anomaly| anomaly[:code] == "accounts_without_contact_details" }
    assert_equal 1, finding[:count]
    assert_equal "blocker", finding[:severity]
  end
end
