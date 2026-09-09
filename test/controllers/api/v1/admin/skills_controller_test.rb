require "test_helper"

class Api::V1::Admin::SkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)   # coach + admin
    @coach = users(:three) # coach role only
    @player = users(:one)  # player role only
    @category = categories(:one)
  end

  test "admin can list skills" do
    sign_in_as(@admin)
    get "/api/v1/admin/skills"
    assert_response :success
    body = JSON.parse(response.body)
    assert body.any? { |s| s["title"] == "MyString" }
  end

  test "admin can show a skill" do
    sign_in_as(@admin)
    get "/api/v1/admin/skills/#{skills(:one).id}"
    assert_response :success
    assert_equal "MyString", JSON.parse(response.body)["title"]
  end

  test "admin can create a skill" do
    sign_in_as(@admin)
    post "/api/v1/admin/skills", params: { skill: { title: "New Skill", category_id: @category.id, description: "Desc" } }
    assert_response :created
    assert_equal "New Skill", Skill.find_by(title: "New Skill").title
  end

  test "admin can update a skill" do
    skill = skills(:one)
    sign_in_as(@admin)
    patch "/api/v1/admin/skills/#{skill.id}", params: { skill: { title: "Updated" } }
    assert_response :success
    assert_equal "Updated", skill.reload.title
  end

  test "admin can delete a skill not used by drills" do
    skill = Skill.create!(title: "Orphan", category_id: @category.id)
    sign_in_as(@admin)
    delete "/api/v1/admin/skills/#{skill.id}"
    assert_response :no_content
    assert_not Skill.exists?(skill.id)
  end

  test "admin cannot delete a skill used by drills" do
    skill = skills(:one)
    drill = drills(:one)
    DrillSkill.create!(drill: drill, skill: skill)
    sign_in_as(@admin)
    delete "/api/v1/admin/skills/#{skill.id}"
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_match(/used by 1 drill/, body["error"])
    assert Skill.exists?(skill.id)
  end

  test "validation errors return 422" do
    sign_in_as(@admin)
    post "/api/v1/admin/skills", params: { skill: { title: "", category_id: @category.id } }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "coach cannot access admin skills" do
    sign_in_as(@coach)
    get "/api/v1/admin/skills"
    assert_response :forbidden
  end

  test "player cannot access admin skills" do
    sign_in_as(@player)
    get "/api/v1/admin/skills"
    assert_response :forbidden
  end

  test "unauthenticated cannot access admin skills" do
    get "/api/v1/admin/skills"
    assert_response :unauthorized
  end
end
