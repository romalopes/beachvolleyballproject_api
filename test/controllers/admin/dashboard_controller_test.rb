require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)   # coach + admin
    @player = users(:one)  # player role only
  end

  test "admin can view settings dashboard" do
    sign_in_as(@admin)
    get "/admin/settings"
    assert_response :success
    assert_select "h1", "Settings"
  end

  test "non-admin is redirected from settings dashboard" do
    sign_in_as(@player)
    get "/admin/settings"
    assert_redirected_to root_path
  end

  test "unauthenticated is redirected to sign in" do
    get "/admin/settings"
    assert_redirected_to new_session_path
  end
end