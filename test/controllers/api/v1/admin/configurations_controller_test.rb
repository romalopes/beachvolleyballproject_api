require "test_helper"

class Api::V1::Admin::ConfigurationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)   # coach + admin
    @player = users(:one)  # player role only
    AppSetting.delete_all
  end

  test "admin gets default configuration" do
    sign_in_as(@admin)
    get "/api/v1/admin/configuration"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["logs_saved_to_database"]
    assert_equal false, body["test"]
    assert_equal "romalopes@yahoo.com.br", body["test_email"]
  end

  test "admin can update all settings" do
    sign_in_as(@admin)
    patch "/api/v1/admin/configuration",
          params: { logs_saved_to_database: false, test: true, test_email: "qa@example.com" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["logs_saved_to_database"]
    assert_equal true, body["test"]
    assert_equal "qa@example.com", body["test_email"]
    assert_equal false, AppSetting.logs_enabled?
    assert_equal true, AppSetting.test?
    assert_equal "qa@example.com", AppSetting.test_email
  end

  test "partial update leaves other settings untouched" do
    sign_in_as(@admin)
    patch "/api/v1/admin/configuration", params: { test: true }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["logs_saved_to_database"]
    assert_equal true, body["test"]
    assert_equal "romalopes@yahoo.com.br", body["test_email"]
  end

  test "disabling logs stops LogService persistence" do
    sign_in_as(@admin)
    patch "/api/v1/admin/configuration", params: { logs_saved_to_database: false }
    assert_response :success
    assert_no_difference("Log.count") do
      LogService.log(description: "Should not persist", action: "show", method: "GET")
    end
  end

  test "non-admin cannot read configuration" do
    sign_in_as(@player)
    get "/api/v1/admin/configuration"
    assert_response :forbidden
  end

  test "non-admin cannot update configuration" do
    sign_in_as(@player)
    patch "/api/v1/admin/configuration", params: { logs_saved_to_database: false }
    assert_response :forbidden
    assert_equal true, AppSetting.logs_enabled?
  end

  test "guest cannot read configuration" do
    get "/api/v1/admin/configuration"
    assert_response :unauthorized
  end

  test "test mode redirects outgoing mail to the configured address" do
    sign_in_as(@admin)
    AppSetting.set!(:test, true)
    AppSetting.set!(:test_email, "romalopes@yahoo.com.br")
    email = PasswordsMailer.reset_password_instructions(users(:one)).deliver_now
    assert_equal ["romalopes@yahoo.com.br"], email.to
    assert_match(/\[TEST\]/, email.subject)
  end
end