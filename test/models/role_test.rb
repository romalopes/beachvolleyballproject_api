require "test_helper"

class RoleTest < ActiveSupport::TestCase
  test "role name is unique" do
    Role.create!(name: "unique_role")
    assert_raises(ActiveRecord::RecordInvalid) do
      Role.create!(name: "unique_role")
    end
  end

  test "role requires a name" do
    role = Role.new
    assert_not role.valid?
    assert_includes role.errors[:name], "can't be blank"
  end

  test "role can belong to multiple users" do
    role = roles(:player)
    assert_operator role.users.count, :>=, 1
  end
end
