require "test_helper"

class Api::V1::Admin::LogsControllerTest < ActionDispatch::IntegrationTest
  # Disable transactional tests so that logs created by one request are visible
  # to subsequent requests in the same test (integration tests run each request
  # in a separate thread with its own database connection).
  self.use_transactional_tests = false

  setup do
    @admin = users(:two)   # coach + admin
    @coach = users(:three) # coach role only
    @player = users(:one)  # player role only
    @category = categories(:one)
    @skill = skills(:one)
    LogObject.delete_all
    Log.delete_all
  end

  teardown do
    LogObject.delete_all
    Log.delete_all
  end

  test "admin can list logs" do
    sign_in_as(@admin)
    post "/api/v1/admin/skills", params: { skill: { title: "Log Test Skill", category_id: @category.id } }
    assert_response :created
    get "/api/v1/admin/logs"
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("data")
    assert body.key?("meta")
    assert body["data"].length >= 1
  end

  test "admin can show a log" do
    sign_in_as(@admin)
    post "/api/v1/admin/skills", params: { skill: { title: "Show Test", category_id: @category.id } }
    assert_response :created
    log = Log.last
    get "/api/v1/admin/logs/#{log.id}"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal log.id, body["data"]["id"]
    assert_match(/Show Test/, body["data"]["description"])
  end

  test "admin can filter logs by action" do
    sign_in_as(@admin)
    post "/api/v1/admin/skills", params: { skill: { title: "Filter Test", category_id: @category.id } }
    assert_response :created
    get "/api/v1/admin/logs", params: { action_filter: "create" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body["data"].all? { |l| l["action"] == "create" }
  end

  test "admin can filter logs by user" do
    sign_in_as(@admin)
    post "/api/v1/admin/skills", params: { skill: { title: "User Filter Test", category_id: @category.id } }
    assert_response :created
    get "/api/v1/admin/logs", params: { user_id: @admin.id }
    assert_response :success
    body = JSON.parse(response.body)
    assert body["data"].all? { |l| l["user"] && l["user"]["id"] == @admin.id }
  end

  test "admin can filter logs by object" do
    sign_in_as(@admin)
    post "/api/v1/admin/skills", params: { skill: { title: "Object Filter Test", category_id: @category.id } }
    assert_response :created
    skill = Skill.last
    get "/api/v1/admin/logs", params: { object_type: "Skill", object_id: skill.id }
    assert_response :success
    body = JSON.parse(response.body)
    assert body["data"].any? { |l| l["description"].include?("Object Filter Test") }
  end

  test "show returns 404 for nonexistent log" do
    sign_in_as(@admin)
    get "/api/v1/admin/logs/999999"
    assert_response :not_found
  end

  test "coach cannot access logs" do
    sign_in_as(@coach)
    get "/api/v1/admin/logs"
    assert_response :forbidden
  end

  test "player cannot access logs" do
    sign_in_as(@player)
    get "/api/v1/admin/logs"
    assert_response :forbidden
  end

  test "unauthenticated cannot access logs" do
    get "/api/v1/admin/logs"
    assert_response :unauthorized
  end

  test "pagination metadata is correct" do
    sign_in_as(@admin)
    3.times { |i| post "/api/v1/admin/skills", params: { skill: { title: "Page Test #{i}", category_id: @category.id } } }
    get "/api/v1/admin/logs", params: { page: 1, per_page: 2 }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["meta"]["page"]
    assert_equal 2, body["meta"]["per_page"]
    assert body["meta"]["total"] >= 3
    assert body["meta"]["total_pages"] >= 2
  end

  test "log detail includes full object info" do
    sign_in_as(@admin)
    post "/api/v1/admin/skills", params: { skill: { title: "Detail Test", category_id: @category.id } }
    assert_response :created
    log = Log.last
    get "/api/v1/admin/logs/#{log.id}"
    assert_response :success
    body = JSON.parse(response.body)
    obj = body["data"]["objects"].first
    assert_equal "Skill", obj["type"]
    assert_equal true, obj["exists"]
  end

  test "log detail shows deleted objects" do
    sign_in_as(@admin)
    post "/api/v1/admin/skills", params: { skill: { title: "Delete Obj Test", category_id: @category.id } }
    assert_response :created
    log = Log.last
    skill = Skill.last
    delete "/api/v1/admin/skills/#{skill.id}"
    assert_response :no_content
    get "/api/v1/admin/logs/#{log.id}"
    assert_response :success
    body = JSON.parse(response.body)
    obj = body["data"]["objects"].first
    assert_equal false, obj["exists"]
    assert_nil obj["label"]
  end

  test "creating a skill generates a log" do
    sign_in_as(@admin)
    assert_difference -> { Log.count }, 1 do
      post "/api/v1/admin/skills", params: { skill: { title: "Logged Skill", category_id: @category.id } }
    end
    assert_response :created
    log = Log.last
    assert_equal "create", log.action
    assert_match(/Logged Skill/, log.description)
  end

  test "updating a skill generates a log" do
    sign_in_as(@admin)
    assert_difference -> { Log.count }, 1 do
      patch "/api/v1/admin/skills/#{@skill.id}", params: { skill: { title: "Renamed" } }
    end
    assert_response :success
    log = Log.last
    assert_equal "update", log.action
    assert_equal @skill, log.log_objects.first.object
  end

  test "deleting a skill generates a log" do
    sign_in_as(@admin)
    orphan = Skill.create!(title: "Deletable", category_id: @category.id)
    assert_difference -> { Log.count }, 1 do
      delete "/api/v1/admin/skills/#{orphan.id}"
    end
    assert_response :no_content
    log = Log.last
    assert_equal "destroy", log.action
    assert_equal orphan.id, log.log_objects.first.object_id
  end

  test "show action generates a log" do
    sign_in_as(@admin)
    assert_difference -> { Log.count }, 1 do
      get "/api/v1/admin/skills/#{@skill.id}"
    end
    assert_response :success
    log = Log.last
    assert_equal "show", log.action
  end

  test "admin can read rails log file tail" do
    sign_in_as(@admin)
    get "/api/v1/admin/system_logs", params: { lines: 10 }
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("lines")
    assert_instance_of Array, body["lines"]
  end

  test "system logs rejects lines above the maximum" do
    sign_in_as(@admin)
    get "/api/v1/admin/system_logs", params: { lines: 99_999 }
    assert_response :success
    # clamped rather than erroring; response remains valid JSON
    body = JSON.parse(response.body)
    assert_instance_of Array, body["lines"]
  end

  test "player cannot access system logs" do
    sign_in_as(@player)
    get "/api/v1/admin/system_logs"
    assert_response :forbidden
  end

  test "unauthenticated cannot access system logs" do
    get "/api/v1/admin/system_logs"
    assert_response :unauthorized
  end
end
