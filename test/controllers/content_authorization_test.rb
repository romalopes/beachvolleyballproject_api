require "test_helper"

class ContentAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @player = users(:one)   # player role only
    @admin = users(:two)    # coach + admin
    @coach = users(:three)  # coach role only
    @category = categories(:one)
  end

  test "coach can create a skill" do
    sign_in_as(@coach)
    post "/api/v1/skills", params: { skill: { title: "New Skill", category_id: @category.id } }
    assert_response :created
    assert_equal @coach.id, Skill.find_by(title: "New Skill").created_by_id
  end

  test "player cannot create a skill" do
    sign_in_as(@player)
    post "/api/v1/skills", params: { skill: { title: "Blocked", category_id: @category.id } }
    assert_response :forbidden
  end

  test "guest cannot create a skill" do
    post "/api/v1/skills", params: { skill: { title: "Blocked", category_id: @category.id } }
    assert_response :unauthorized
  end

  test "coach can update their own skill" do
    skill = Skill.create!(title: "Owned", category_id: @category.id, created_by: @coach)
    sign_in_as(@coach)
    patch "/api/v1/skills/#{skill.id}", params: { skill: { title: "Updated" } }
    assert_response :success
    assert_equal "Updated", skill.reload.title
  end

  test "coach cannot update another coach's skill" do
    skill = Skill.create!(title: "Other", category_id: @category.id, created_by: @admin)
    sign_in_as(@coach)
    patch "/api/v1/skills/#{skill.id}", params: { skill: { title: "Hacked" } }
    assert_response :forbidden
  end

  test "admin can update any skill" do
    skill = Skill.create!(title: "Any", category_id: @category.id, created_by: @coach)
    sign_in_as(@admin)
    patch "/api/v1/skills/#{skill.id}", params: { skill: { title: "Admin updated" } }
    assert_response :success
    assert_equal "Admin updated", skill.reload.title
  end
end
