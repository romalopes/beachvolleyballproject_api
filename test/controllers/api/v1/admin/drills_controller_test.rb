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
end
