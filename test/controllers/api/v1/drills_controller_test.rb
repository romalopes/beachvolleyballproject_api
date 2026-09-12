require "test_helper"

class Api::V1::DrillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)    # coach + admin
    @coach = users(:three)  # coach role only
    @player = users(:one)   # player role only
    @owned = Drill.create!(
      title: "Owned Drill",
      setup_instructions: "Setup",
      training_stage: "beginning",
      difficulty_level: "beginner",
      min_players: 2,
      max_players: 8,
      ideal_num_players: 4,
      created_by: @coach
    )
  end

  # ---------- index / show (public) ----------

  test "index is public and excludes the raw definition column" do
    get "/api/v1/drills"
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body
    drill = body.find { |d| d["slug"] == "mystring-one" }
    assert_not_nil drill
    assert_not drill.key?("definition")
    assert drill.key?("skills")
  end

  test "show is public and includes skills, media_assets and training_sessions" do
    get "/api/v1/drills/mystring-one"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "mystring-one", body["slug"]
    assert body.key?("skills")
    assert body.key?("media_assets")
    assert body.key?("training_sessions")
  end

  test "show falls back to lookup by id" do
    drill = drills(:one)
    get "/api/v1/drills/#{drill.id}"
    assert_response :success
    assert_equal drill.id, JSON.parse(response.body)["id"]
  end

  test "show of an unknown slug renders null (recorded behavior)" do
    # NOTE: set_drill finds nothing and @drill is nil, so the controller
    # renders `null` with 200. Ideally this would be a 404
    # { error: "Drill not found" } — recorded here so a future fix is visible.
    sign_in_as(@coach)
    get "/api/v1/drills/no-such-drill"
    assert_response :success
    assert_nil JSON.parse(response.body)
  end

  # ---------- create ----------

  test "coach can create a drill" do
    sign_in_as(@coach)
    assert_difference("Drill.count") do
      post "/api/v1/drills", params: { drill: {
        title: "New Drill",
        setup_instructions: "Warm up",
        training_stage: "warmup",
        difficulty_level: "beginner",
        min_players: 2,
        max_players: 6,
        ideal_num_players: 4
      } }
    end
    assert_response :created
    assert_equal @coach.id, Drill.find_by(title: "New Drill").created_by_id
  end

  test "player cannot create a drill" do
    sign_in_as(@player)
    post "/api/v1/drills", params: { drill: {
      title: "Blocked", training_stage: "warmup", difficulty_level: "beginner",
      min_players: 2, max_players: 4, ideal_num_players: 2
    } }
    assert_response :forbidden
  end

  test "guest cannot create a drill" do
    post "/api/v1/drills", params: { drill: {
      title: "Blocked", training_stage: "warmup", difficulty_level: "beginner",
      min_players: 2, max_players: 4, ideal_num_players: 2
    } }
    assert_response :unauthorized
  end

  test "create returns 422 on validation errors" do
    sign_in_as(@coach)
    post "/api/v1/drills", params: { drill: { title: "" } }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  # ---------- update / destroy (owner or admin) ----------

  test "owner can update their drill" do
    sign_in_as(@coach)
    patch "/api/v1/drills/#{@owned.slug}", params: { drill: { title: "Renamed" } }
    assert_response :success
    assert_equal "Renamed", @owned.reload.title
  end

  test "non-owner coach cannot update another coach's drill" do
    other = Drill.create!(
      title: "Admins Drill",
      training_stage: "middle",
      difficulty_level: "intermediate",
      min_players: 2, max_players: 4, ideal_num_players: 2,
      created_by: @admin
    )
    sign_in_as(@coach)
    patch "/api/v1/drills/#{other.slug}", params: { drill: { title: "Hacked" } }
    assert_response :forbidden
  end

  test "admin can update any drill" do
    sign_in_as(@admin)
    patch "/api/v1/drills/#{@owned.slug}", params: { drill: { title: "Admin edited" } }
    assert_response :success
    assert_equal "Admin edited", @owned.reload.title
  end

  test "update returns 422 on validation errors" do
    sign_in_as(@coach)
    patch "/api/v1/drills/#{@owned.slug}", params: { drill: { min_players: 99, max_players: 1 } }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "owner can destroy their drill" do
    sign_in_as(@coach)
    assert_difference("Drill.count", -1) do
      delete "/api/v1/drills/#{@owned.slug}"
    end
    assert_response :no_content
  end

  test "guest cannot destroy a drill" do
    delete "/api/v1/drills/#{@owned.slug}"
    assert_response :unauthorized
    assert Drill.exists?(@owned.id)
  end
end
