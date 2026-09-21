require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  setup do
    AppSetting.delete_all
  end

  test "defaults apply when no rows exist" do
    assert_equal true, AppSetting.logs_enabled?
    assert_equal false, AppSetting.test?
    assert_equal "romalopes@yahoo.com.br", AppSetting.test_email
  end

  test "logs_enabled? reflects persisted value" do
    AppSetting.set!(:logs_enabled, false)
    assert_equal false, AppSetting.logs_enabled?
    AppSetting.set!(:logs_enabled, true)
    assert_equal true, AppSetting.logs_enabled?
  end

  test "test? and test_email reflect persisted values" do
    AppSetting.set!(:test, true)
    assert_equal true, AppSetting.test?
    AppSetting.set!(:test_email, "qa@example.com")
    assert_equal "qa@example.com", AppSetting.test_email
  end

  test "boolean casts string values" do
    AppSetting.set!(:test, "false")
    assert_equal false, AppSetting.test?
    AppSetting.set!(:test, "true")
    assert_equal true, AppSetting.test?
  end

  test "ordered_all includes unset built-in defaults sorted by key" do
    rows = AppSetting.ordered_all
    assert_equal %w[logs_enabled test test_email], rows.map(&:key)
    AppSetting.set!(:custom_b, "x")
    AppSetting.set!(:custom_a, "y")
    assert_equal %w[custom_a custom_b logs_enabled test test_email],
                 AppSetting.ordered_all.map(&:key)
  end

  test "string falls back to default when row is missing" do
    assert_equal "romalopes@yahoo.com.br", AppSetting.string("test_email")
  end
end