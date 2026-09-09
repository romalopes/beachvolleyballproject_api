require "test_helper"

class Admin::SkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)   # coach + admin
    @player = users(:one)  # player role only
    @category = categories(:one)
  end

  test "admin can list skills" do
    sign_in_as(@admin)
    get "/admin/skills"
    assert_response :success
    assert_select "h1", "Skills"
  end

  test "admin can view skill" do
    sign_in_as(@admin)
    get "/admin/skills/#{skills(:one).id}"
    assert_response :success
    assert_select "h2", "MyString"
  end

  test "admin can visit new skill form" do
    sign_in_as(@admin)
    get "/admin/skills/new"
    assert_response :success
    assert_select "h1", "New Skill"
  end

  test "admin can create a skill" do
    sign_in_as(@admin)
    post "/admin/skills", params: { skill: { title: "Brand New", category_id: @category.id, description: "Desc" } }
    assert_redirected_to admin_skill_path(Skill.find_by(title: "Brand New"))
    assert_equal "Brand New", Skill.find_by(title: "Brand New").title
  end

  test "admin can visit edit skill form" do
    sign_in_as(@admin)
    get "/admin/skills/#{skills(:one).id}/edit"
    assert_response :success
    assert_select "h1", "Edit Skill"
  end

  test "admin can update a skill" do
    sign_in_as(@admin)
    patch "/admin/skills/#{skills(:one).id}", params: { skill: { title: "Updated" } }
    assert_redirected_to admin_skill_path(skills(:one).reload)
    assert_equal "Updated", skills(:one).reload.title
  end

  test "admin can delete an unused skill" do
    skill = Skill.create!(title: "Orphan", category_id: @category.id)
    sign_in_as(@admin)
    delete "/admin/skills/#{skill.id}"
    assert_redirected_to admin_skills_path
    assert_not Skill.exists?(skill.id)
  end

  test "admin cannot delete a skill used by drills" do
    skill = skills(:one)
    DrillSkill.create!(drill: drills(:one), skill: skill)
    sign_in_as(@admin)
    delete "/admin/skills/#{skill.id}"
    assert_redirected_to admin_skills_path
    assert Skill.exists?(skill.id)
  end

  test "non-admin is redirected from skills index" do
    sign_in_as(@player)
    get "/admin/skills"
    assert_redirected_to root_path
  end
end