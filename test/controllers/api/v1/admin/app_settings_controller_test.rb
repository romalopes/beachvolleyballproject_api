require "test_helper"

class Api::V1::Admin::AppSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)   # coach + admin
    @player = users(:one)  # player role only
    AppSetting.delete_all
  end

  test "admin lists settings including unset built-in defaults" do
    sign_in_as(@admin)
    get "/api/v1/admin/app_settings"
    assert_response :success
    body = JSON.parse(response.body)
    keys = body["settings"].map { |s| s["key"] }
    assert_includes keys, "logs_enabled"
    assert_includes keys, "test"
    assert_includes keys, "test_email"
    assert_equal keys.sort, keys
  end

  test "admin can create a custom setting" do
    sign_in_as(@admin)
    assert_difference("AppSetting.count", 1) do
      post "/api/v1/admin/app_settings",
           params: { key: "maintenance_banner", value: "true" }
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "maintenance_banner", body["key"]
    assert_equal "true", body["value"]
    assert_equal false, body["built_in"]
  end

  test "create rejects blank and duplicate keys" do
    sign_in_as(@admin)
    post "/api/v1/admin/app_settings", params: { key: "", value: "x" }
    assert_response :unprocessable_entity

    AppSetting.set!(:custom_one, "1")
    post "/api/v1/admin/app_settings", params: { key: "custom_one", value: "2" }
    assert_response :unprocessable_entity
  end

  test "admin can update a setting value" do
    AppSetting.set!(:custom_one, "old")
    sign_in_as(@admin)
    patch "/api/v1/admin/app_settings/custom_one", params: { value: "new" }
    assert_response :success
    assert_equal "new", JSON.parse(response.body)["value"]
    assert_equal "new", AppSetting.find_by(key: "custom_one").value
  end

  test "update of unknown key returns not found" do
    sign_in_as(@admin)
    patch "/api/v1/admin/app_settings/nope", params: { value: "x" }
    assert_response :not_found
  end

  test "admin can delete a custom setting" do
    AppSetting.set!(:custom_one, "1")
    sign_in_as(@admin)
    assert_difference("AppSetting.count", -1) do
      delete "/api/v1/admin/app_settings/custom_one"
    end
    assert_response :no_content
  end

  test "built-in settings cannot be deleted" do
    AppSetting.set!(:test, true)
    sign_in_as(@admin)
    delete "/api/v1/admin/app_settings/test"
    assert_response :unprocessable_entity
    assert_not_nil AppSetting.find_by(key: "test")
  end

  test "non-admin cannot manage settings" do
    sign_in_as(@player)
    get "/api/v1/admin/app_settings"
    assert_response :forbidden
    post "/api/v1/admin/app_settings", params: { key: "x", value: "y" }
    assert_response :forbidden
  end

  test "guest cannot manage settings" do
    get "/api/v1/admin/app_settings"
    assert_response :unauthorized
  end
end
