require "test_helper"

class LogTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
    @category = categories(:one)
  end

  test "valid log with all fields" do
    log = Log.new(
      description: "Created category \"Blocking\"",
      action: "create",
      method: "POST",
      user: @user,
      path: "/api/v1/admin/categories",
      request_id: "abc123",
      ip_address: "127.0.0.1",
      user_agent: "Test",
      status: 201
    )
    assert log.valid?
  end

  test "description is required" do
    log = Log.new(action: "create", method: "POST")
    assert_not log.valid?
    assert log.errors[:description].any?
  end

  test "action is required" do
    log = Log.new(description: "Test", method: "POST")
    assert_not log.valid?
    assert log.errors[:action].any?
  end

  test "method is required" do
    log = Log.new(description: "Test", action: "create")
    assert_not log.valid?
    assert log.errors[:method].any?
  end

  test "user is optional" do
    log = Log.new(
      description: "System action",
      action: "create",
      method: "POST"
    )
    assert log.valid?
    assert_nil log.user_id
  end

  test "recent scope orders by created_at desc" do
    Log.delete_all
    old = Log.create!(description: "Old", action: "create", method: "POST", created_at: 2.days.ago)
    new = Log.create!(description: "New", action: "create", method: "POST", created_at: 1.hour.ago)
    assert_equal [new, old], Log.recent(10).to_a
  end

  test "for_action scope filters by action" do
    Log.delete_all
    Log.create!(description: "Created", action: "create", method: "POST")
    Log.create!(description: "Updated", action: "update", method: "PATCH")
    assert_equal 1, Log.for_action("create").count
  end

  test "for_user scope filters by user" do
    Log.delete_all
    Log.create!(description: "By user", action: "create", method: "POST", user: @user)
    Log.create!(description: "Anonymous", action: "create", method: "POST")
    assert_equal 1, Log.for_user(@user.id).count
  end

  test "for_request scope filters by request_id" do
    Log.delete_all
    Log.create!(description: "Req 1", action: "create", method: "POST", request_id: "req-1")
    Log.create!(description: "Req 2", action: "create", method: "POST", request_id: "req-2")
    assert_equal 1, Log.for_request("req-1").count
  end

  test "for_object scope filters by polymorphic object" do
    Log.delete_all
    log1 = Log.create!(description: "Log 1", action: "create", method: "POST")
    log2 = Log.create!(description: "Log 2", action: "create", method: "POST")
    LogObject.create!(log: log1, object: @category)
    LogObject.create!(log: log2, object: skills(:one))
    assert_equal [log1.id], Log.for_object("Category", @category.id).pluck(:id)
  end
end
