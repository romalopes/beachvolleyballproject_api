require "test_helper"

class UserRoleTest < ActiveSupport::TestCase
  test "belongs to user and role" do
    ur = user_roles(:one_player)
    assert_equal users(:one), ur.user
    assert_equal roles(:player), ur.role
  end

  test "duplicate user/role assignment is prevented at the model level" do
    user = users(:one)
    user.add_role(:player)
    assert_equal 1, user.user_roles.where(role: roles(:player)).count
  end
end
