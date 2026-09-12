require "test_helper"

class Api::V1::Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)    # coach + admin (the fixture admin)
    @coach = users(:three)  # coach role only
    @player = users(:one)   # player role only
  end

  test "admin can remove a role from another user" do
    sign_in_as(@admin)
    delete "/api/v1/admin/users/#{@coach.id}/roles/coach"
    assert_response :success
    refute_includes JSON.parse(response.body)["roles"], "coach"
  end

  test "admin can remove their own non-admin role" do
    sign_in_as(@admin)
    assert @admin.has_role?(:coach)
    delete "/api/v1/admin/users/#{@admin.id}/roles/coach"
    assert_response :success
    roles = JSON.parse(response.body)["roles"]
    refute_includes roles, "coach"
    assert_includes roles, "admin"
  end

  test "admin cannot remove their own admin role" do
    sign_in_as(@admin)
    delete "/api/v1/admin/users/#{@admin.id}/roles/admin"
    assert_response :unprocessable_entity
    assert_equal "You cannot remove your own admin role", JSON.parse(response.body)["error"]
    assert @admin.reload.has_role?(:admin), "admin role should be preserved"
  end

  test "admin can remove another admin's admin role when another admin remains" do
    @coach.add_role(:admin) # now two admins exist
    sign_in_as(@admin)
    delete "/api/v1/admin/users/#{@coach.id}/roles/admin"
    assert_response :success
    refute_includes JSON.parse(response.body)["roles"], "admin"
    assert @admin.reload.has_role?(:admin), "the caller's own admin role is untouched"
  end

  test "self-guard takes precedence over the last-admin guard" do
    sign_in_as(@admin) # @admin is the only admin in fixtures
    delete "/api/v1/admin/users/#{@admin.id}/roles/admin"
    assert_response :unprocessable_entity
    assert_equal "You cannot remove your own admin role", JSON.parse(response.body)["error"]
  end

  test "guest cannot remove a role" do
    delete "/api/v1/admin/users/#{@coach.id}/roles/coach"
    assert_response :unauthorized
  end

  test "non-admin cannot remove a role" do
    sign_in_as(@player)
    delete "/api/v1/admin/users/#{@coach.id}/roles/coach"
    assert_response :forbidden
  end
end