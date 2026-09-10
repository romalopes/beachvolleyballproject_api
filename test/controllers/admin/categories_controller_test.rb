require "test_helper"

class Admin::CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)   # coach + admin
    @player = users(:one)  # player role only
  end

  test "admin can list categories" do
    sign_in_as(@admin)
    get "/admin/categories"
    assert_response :success
    assert_select "h1", "Categories"
  end

  test "admin can view category" do
    sign_in_as(@admin)
    get "/admin/categories/#{categories(:one).id}"
    assert_response :success
    assert_select "h2", "MyString"
  end

  test "admin can create a category" do
    sign_in_as(@admin)
    post "/admin/categories", params: { category: { name: "New Category" } }
    assert_redirected_to admin_category_path(Category.find_by(name: "New Category"))
    assert_equal "New Category", Category.find_by(name: "New Category").name
  end

  test "admin can update a category" do
    sign_in_as(@admin)
    patch "/admin/categories/#{categories(:one).id}", params: { category: { name: "Updated" } }
    assert_redirected_to admin_category_path(categories(:one).reload)
    assert_equal "Updated", categories(:one).reload.name
  end

  test "admin cannot delete a category with skills" do
    sign_in_as(@admin)
    delete "/admin/categories/#{categories(:one).id}"
    assert_redirected_to admin_categories_path
    assert Category.exists?(categories(:one).id)
  end

  test "non-admin is redirected from categories index" do
    sign_in_as(@player)
    get "/admin/categories"
    assert_redirected_to root_path
  end

  test "admin categories index shows total count" do
    sign_in_as(@admin)
    get "/admin/categories"
    assert_response :success
    assert_includes response.body, "#{Category.count} categor"
  end

  test "admin categories index links skill counts to filtered skills" do
    sign_in_as(@admin)
    get "/admin/categories"
    assert_response :success
    assert_select "a[href=?]", admin_skills_path(category_id: categories(:one).id)
  end
end