require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "can have multiple roles" do
    user = users(:two)
    assert_includes user.roles.pluck(:name), "coach"
    assert_includes user.roles.pluck(:name), "admin"
  end

  test "has_role? works" do
    assert users(:two).has_role?(:coach)
    assert_not users(:two).has_role?(:player)
  end

  test "role predicate methods work" do
    user = users(:two)
    assert user.coach?
    assert user.admin?
    assert_not user.player?
  end

  test "add_role is idempotent and finds by name" do
    user = users(:one)
    result = user.add_role(:coach)
    assert result
    assert user.coach?

    # Adding again should not duplicate
    user.add_role(:coach)
    assert_equal 1, user.user_roles.where(role: roles(:coach)).count
  end

  test "add_role fails safely for unknown role" do
    user = users(:one)
    assert_not user.add_role(:nonexistent_role)
  end

  test "remove_role works" do
    user = users(:two)
    user.remove_role(:admin)
    assert_not user.admin?
    assert user.coach?
  end

  test "remove_role fails safely for unknown role" do
    user = users(:one)
    assert_not user.remove_role(:nonexistent_role)
  end
end
