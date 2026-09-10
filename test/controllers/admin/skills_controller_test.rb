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

  test "admin can search skills by name" do
    sign_in_as(@admin)
    get "/admin/skills", params: { q: skills(:one).title[0, 4] }
    assert_response :success
    assert_includes response.body, skills(:one).title
  end

  test "admin search with no match shows filter empty state" do
    sign_in_as(@admin)
    get "/admin/skills", params: { q: "zzz-no-such-skill-zzz" }
    assert_response :success
    assert_includes response.body, "No skills match these filters"
  end

  test "admin can filter skills by category" do
    sign_in_as(@admin)
    get "/admin/skills", params: { category_id: skills(:one).category_id }
    assert_response :success
    assert_includes response.body, skills(:one).title
  end

  test "admin unknown category filter is ignored" do
    sign_in_as(@admin)
    get "/admin/skills", params: { category_id: 999_999 }
    assert_response :success
    assert_includes response.body, skills(:one).title
  end

  test "admin can sort skills by name descending" do
    sign_in_as(@admin)
    get "/admin/skills", params: { sort: "name-desc" }
    assert_response :success
    titles = Skill.order(title: :desc).pluck(:title)
    assert_includes response.body, titles.first if titles.any?
  end

  test "admin can sort skills by category" do
    sign_in_as(@admin)
    get "/admin/skills", params: { sort: "category" }
    assert_response :success
  end

  test "admin unknown sort is ignored" do
    sign_in_as(@admin)
    get "/admin/skills", params: { sort: "nope" }
    assert_response :success
    assert_includes response.body, skills(:one).title
  end

  test "admin skills index shows category context with back link" do
    sign_in_as(@admin)
    get "/admin/skills", params: { category_id: skills(:one).category_id }
    assert_response :success
    assert_includes response.body, "Showing skills in"
    assert_includes response.body, skills(:one).category.name
    assert_select "a[href=?]", admin_categories_path, text: "Back to Categories"
  end

  test "admin skills index shows no category context for unknown category" do
    sign_in_as(@admin)
    get "/admin/skills", params: { category_id: 999_999 }
    assert_response :success
    assert_not_includes response.body, "Showing skills in"
  end

  test "admin skills index has general back link" do
    sign_in_as(@admin)
    get "/admin/skills"
    assert_response :success
    assert_includes response.body, "Back</a>"
  end

  test "admin skills index shows total count" do
    sign_in_as(@admin)
    get "/admin/skills"
    assert_response :success
    assert_includes response.body, "#{Skill.count} skill"
  end

  test "admin skills index links drill counts to filtered drills" do
    DrillSkill.create!(drill: drills(:one), skill: skills(:one))
    sign_in_as(@admin)
    get "/admin/skills"
    assert_response :success
    assert_select "a[href=?]", admin_drills_path(skill_id: skills(:one).id)
  end
end