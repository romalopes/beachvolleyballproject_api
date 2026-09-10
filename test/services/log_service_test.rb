require "test_helper"

class LogServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
    @category = categories(:one)
    @skill = skills(:one)
  end

  test "creates a log with all fields" do
    log = LogService.log(
      description: "Created category \"Blocking\"",
      user: @user,
      action: "create",
      method: "POST",
      path: "/api/v1/admin/categories",
      request_id: "req-123",
      ip_address: "127.0.0.1",
      user_agent: "RSpec",
      status: 201,
      objects: [@category]
    )

    assert log.persisted?
    assert_equal "Created category \"Blocking\"", log.description
    assert_equal @user, log.user
    assert_equal "create", log.action
    assert_equal "POST", log.method
    assert_equal "/api/v1/admin/categories", log.path
    assert_equal "req-123", log.request_id
    assert_equal "127.0.0.1", log.ip_address
    assert_equal "RSpec", log.user_agent
    assert_equal 201, log.status
  end

  test "creates polymorphic log objects" do
    log = LogService.log(
      description: "Test",
      action: "create",
      method: "POST",
      objects: [@category, @skill, @user]
    )

    assert_equal 3, log.log_objects.count
    types = log.log_objects.pluck(:object_type).sort
    assert_equal ["Category", "Skill", "User"], types
  end

  test "handles nil user" do
    log = LogService.log(
      description: "System action",
      user: nil,
      action: "create",
      method: "POST"
    )

    assert log.persisted?
    assert_nil log.user_id
  end

  test "skips objects without ids" do
    new_skill = Skill.new(title: "Unsaved")
    log = LogService.log(
      description: "Test",
      action: "create",
      method: "POST",
      objects: [@category, new_skill, nil]
    )

    assert_equal 1, log.log_objects.count
    assert_equal "Category", log.log_objects.first.object_type
  end

  test "returns nil when description is blank" do
    result = LogService.log(description: "", action: "create", method: "POST")
    assert_nil result
  end

  test "returns nil when action is blank" do
    result = LogService.log(description: "Test", action: "", method: "POST")
    assert_nil result
  end

  test "returns nil when method is blank" do
    result = LogService.log(description: "Test", action: "create", method: "")
    assert_nil result
  end

  test "does not raise on database failure" do
    # Simulate a failure by making Log.create! raise an exception
    Log.define_singleton_method(:create!) do |**_args|
      raise ActiveRecord::RecordInvalid.new(Log.new)
    end
    result = LogService.log(description: "Test", action: "create", method: "POST")
    assert_nil result
  ensure
    Log.singleton_class.remove_method(:create!)
  end

  test "description_for generates readable text" do
    desc = LogService.description_for("create", @skill)
    assert_equal "Create Skill \"#{@skill.title}\"", desc
  end

  test "human_label prefers title" do
    assert_equal @skill.title, LogService.human_label(@skill)
  end

  test "human_label falls back to name" do
    assert_equal @category.name, LogService.human_label(@category)
  end

  test "human_label falls back to id" do
    record = User.new(id: 42)
    assert_equal "#42", LogService.human_label(record)
  end
end
