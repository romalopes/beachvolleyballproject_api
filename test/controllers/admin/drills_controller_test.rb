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

  test "admin can search drills by name" do
    sign_in_as(@admin)
    get "/admin/drills", params: { q: drills(:one).title[0, 4] }
    assert_response :success
    assert_includes response.body, drills(:one).title
  end

  test "admin search with no match shows filter empty state" do
    sign_in_as(@admin)
    get "/admin/drills", params: { q: "zzz-no-such-drill-zzz" }
    assert_response :success
    assert_includes response.body, "No drills match these filters"
  end

  test "admin can filter drills by stage" do
    sign_in_as(@admin)
    stage = drills(:one).training_stage
    get "/admin/drills", params: { stage: stage }
    assert_response :success
    assert_includes response.body, drills(:one).title
  end

  test "admin can filter drills by difficulty" do
    sign_in_as(@admin)
    level = drills(:one).difficulty_level
    get "/admin/drills", params: { difficulty: level }
    assert_response :success
    assert_includes response.body, drills(:one).title
  end

  test "admin can filter drills by min players overlap" do
    sign_in_as(@admin)
    get "/admin/drills", params: { min_players: drills(:one).max_players }
    assert_response :success
    assert_includes response.body, drills(:one).title
  end

  test "admin can filter drills by max players overlap" do
    sign_in_as(@admin)
    get "/admin/drills", params: { max_players: drills(:one).min_players }
    assert_response :success
    assert_includes response.body, drills(:one).title
  end

  test "admin min greater than max shows range error" do
    sign_in_as(@admin)
    get "/admin/drills", params: { min_players: 8, max_players: 2 }
    assert_response :success
    assert_includes response.body, "Min players cannot exceed max players"
  end

  test "admin can sort drills by name descending" do
    sign_in_as(@admin)
    get "/admin/drills", params: { sort: "name-desc" }
    assert_response :success
    titles = Drill.order(title: :desc).pluck(:title)
    assert_includes response.body, titles.first if titles.any?
  end

  test "admin can sort drills by stage" do
    sign_in_as(@admin)
    get "/admin/drills", params: { sort: "stage" }
    assert_response :success
  end

  test "admin can sort drills by difficulty" do
    sign_in_as(@admin)
    get "/admin/drills", params: { sort: "difficulty" }
    assert_response :success
  end

  test "admin unknown filter values are ignored" do
    sign_in_as(@admin)
    get "/admin/drills", params: { stage: "nope", difficulty: "nope", sort: "nope" }
    assert_response :success
    assert_includes response.body, drills(:one).title
  end

  test "admin can filter drills by skill id" do
    DrillSkill.create!(drill: drills(:one), skill: skills(:one))
    sign_in_as(@admin)
    get "/admin/drills", params: { skill_id: skills(:one).id }
    assert_response :success
    assert_includes response.body, drills(:one).title
  end

  test "admin drill filter by skill shows context with back link" do
    sign_in_as(@admin)
    get "/admin/drills", params: { skill_id: skills(:one).id }
    assert_response :success
    assert_includes response.body, "Showing drills linked to"
    assert_includes response.body, skills(:one).title
    assert_select "a[href=?]", admin_skills_path, text: "Back to Skills"
  end

  test "admin drill filter with unknown skill is ignored" do
    sign_in_as(@admin)
    get "/admin/drills", params: { skill_id: 999_999 }
    assert_response :success
    assert_includes response.body, drills(:one).title
  end

  test "admin drills index shows total count" do
    sign_in_as(@admin)
    get "/admin/drills"
    assert_response :success
    assert_includes response.body, "#{Drill.count} drill"
  end

  test "admin drills index has general back link" do
    sign_in_as(@admin)
    get "/admin/drills"
    assert_response :success
    assert_includes response.body, "Back</a>"
  end
end