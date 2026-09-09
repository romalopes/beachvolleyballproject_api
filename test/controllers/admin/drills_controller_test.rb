require "test_helper"

class Admin::DrillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)   # coach + admin
    @player = users(:one)  # player role only
  end

  test "admin can list drills" do
    sign_in_as(@admin)
    get "/admin/drills"
    assert_response :success
    assert_select "h1", "Drills"
  end

  test "admin can view drill" do
    sign_in_as(@admin)
    get "/admin/drills/#{drills(:one).id}"
    assert_response :success
    assert_select "h2", "MyString"
  end

  test "admin can create a drill" do
    sign_in_as(@admin)
    post "/admin/drills", params: {
      drill: {
        title: "New Drill", setup_instructions: "Steps", training_stage: "beginning",
        difficulty_level: "beginner", min_players: 2, max_players: 8, ideal_num_players: 4
      }
    }
    assert_redirected_to admin_drill_path(Drill.find_by(title: "New Drill"))
    assert_equal "New Drill", Drill.find_by(title: "New Drill").title
  end

  test "admin can update a drill" do
    sign_in_as(@admin)
    patch "/admin/drills/#{drills(:one).id}", params: { drill: { title: "Updated" } }
    assert_redirected_to admin_drill_path(drills(:one).reload)
    assert_equal "Updated", drills(:one).reload.title
  end

  test "admin cannot delete a drill with a skill attached" do
    sign_in_as(@admin)
    delete "/admin/drills/#{drills(:one).id}"
    assert_redirected_to admin_drills_path
    assert Drill.exists?(drills(:one).id)
  end

  test "non-admin is redirected from drills index" do
    sign_in_as(@player)
    get "/admin/drills"
    assert_redirected_to root_path
  end
end