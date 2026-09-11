require "test_helper"

class Api::V1::Admin::DrillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)   # coach + admin
    @coach = users(:three) # coach role only
    @player = users(:one)  # player role only
  end

  test "admin can list drills" do
    sign_in_as(@admin)
    get "/api/v1/admin/drills"
    assert_response :success
    body = JSON.parse(response.body)
    assert body.any? { |d| d["title"] == "MyString" }
  end

  test "admin can show a drill" do
    sign_in_as(@admin)
    get "/api/v1/admin/drills/#{drills(:one).id}"
    assert_response :success
    assert_equal "MyString", JSON.parse(response.body)["title"]
  end

  test "admin can create a drill" do
    sign_in_as(@admin)
    post "/api/v1/admin/drills", params: {
      drill: {
        title: "New Drill", setup_instructions: "Instructions", training_stage: "beginning",
        difficulty_level: "beginner", min_players: 2, max_players: 8, ideal_num_players: 4
      }
    }
    assert_response :created
    assert_equal "New Drill", Drill.find_by(title: "New Drill").title
  end

  test "admin can update a drill" do
    drill = drills(:one)
    sign_in_as(@admin)
    patch "/api/v1/admin/drills/#{drill.id}", params: { drill: { title: "Updated" } }
    assert_response :success
    assert_equal "Updated", drill.reload.title
  end

  test "admin can delete a drill with no dependencies" do
    drill = Drill.create!(title: "Orphan", training_stage: "beginning", difficulty_level: "beginner",
                          min_players: 2, max_players: 8, ideal_num_players: 4)
    sign_in_as(@admin)
    delete "/api/v1/admin/drills/#{drill.id}"
    assert_response :no_content
    assert_not Drill.exists?(drill.id)
  end

  test "admin cannot delete a drill with skills" do
    drill = drills(:one)
    DrillSkill.create!(drill: drill, skill: skills(:one))
    sign_in_as(@admin)
    delete "/api/v1/admin/drills/#{drill.id}"
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_match(/skill/, body["error"])
    assert Drill.exists?(drill.id)
  end

  test "validation errors return 422" do
    sign_in_as(@admin)
    post "/api/v1/admin/drills", params: {
      drill: { title: "", training_stage: "beginning", difficulty_level: "beginner",
               min_players: 2, max_players: 8, ideal_num_players: 4 }
    }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "coach cannot access admin drills" do
    sign_in_as(@coach)
    get "/api/v1/admin/drills"
    assert_response :forbidden
  end

  test "player cannot access admin drills" do
    sign_in_as(@player)
    get "/api/v1/admin/drills"
    assert_response :forbidden
  end

  test "unauthenticated cannot access admin drills" do
    get "/api/v1/admin/drills"
    assert_response :unauthorized
  end

  # --- Definition (visualisation JSON) ---

  test "admin can save a valid definition" do
    sign_in_as(@admin)
    valid_def = valid_definition
    post "/api/v1/admin/drills", params: {
      drill: {
        title: "Def Drill", setup_instructions: "Instructions", training_stage: "beginning",
        difficulty_level: "beginner", min_players: 2, max_players: 8, ideal_num_players: 4,
        definition: valid_def
      }
    }, as: :json
    assert_response :created
    drill = Drill.find_by(title: "Def Drill")
    assert_equal 1, drill.definition["version"]
    assert_equal "P1", drill.definition["participants"][0]["id"]
  end

  test "admin show returns the definition" do
    drill = Drill.create!(title: "Show Def", training_stage: "beginning", difficulty_level: "beginner",
                          min_players: 2, max_players: 8, ideal_num_players: 4,
                          definition: valid_definition)
    sign_in_as(@admin)
    get "/api/v1/admin/drills/#{drill.id}"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["definition"]["version"]
    assert body["definition"]["steps"].is_a?(Array)
  end

  test "admin index excludes the definition" do
    Drill.create!(title: "Index Def", training_stage: "beginning", difficulty_level: "beginner",
                  min_players: 2, max_players: 8, ideal_num_players: 4,
                  definition: valid_definition)
    sign_in_as(@admin)
    get "/api/v1/admin/drills"
    assert_response :success
    body = JSON.parse(response.body)
    refute body.any? { |d| d.key?("definition") }, "index should not include definition"
  end

  test "invalid definition returns 422 with errors" do
    sign_in_as(@admin)
    invalid_def = valid_definition.merge("version" => 99)
    post "/api/v1/admin/drills", params: {
      drill: {
        title: "Bad Def", setup_instructions: "Instructions", training_stage: "beginning",
        difficulty_level: "beginner", min_players: 2, max_players: 8, ideal_num_players: 4,
        definition: invalid_def
      }
    }, as: :json
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any? { |e| e.downcase.include?("definition") }
  end

  private

  def valid_definition
    {
      "version" => 1,
      "view" => { "orientation" => "top_down" },
      "court" => { "grid" => { "columns" => 5, "rows" => 4 } },
      "participants" => [{ "id" => "P1", "type" => "player" }],
      "balls" => [{ "id" => "B1", "type" => "volleyball" }],
      "objects" => [],
      "steps" => [
        {
          "id" => "S1",
          "participants" => [{ "id" => "P1", "active" => true, "location" => { "court" => "court_1", "x" => 3, "y" => 2 } }],
          "balls" => [{ "id" => "B1", "active" => true, "location" => { "court" => "court_1", "x" => 3, "y" => 2 } }],
          "objects" => [],
          "actions" => [],
          "participant_movements" => [],
          "ball_movements" => [],
          "object_movements" => [],
        },
      ],
    }
  end
end

