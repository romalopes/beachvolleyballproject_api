require "test_helper"

class Api::V1::Admin::CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)   # coach + admin
    @coach = users(:three) # coach role only
    @player = users(:one)  # player role only
  end

  test "admin can list categories" do
    sign_in_as(@admin)
    get "/api/v1/admin/categories"
    assert_response :success
    body = JSON.parse(response.body)
    assert body.any? { |c| c["name"] == "MyString" }
  end

  test "admin can show a category" do
    sign_in_as(@admin)
    get "/api/v1/admin/categories/#{categories(:one).id}"
    assert_response :success
    assert_equal "MyString", JSON.parse(response.body)["name"]
  end

  test "admin can create a category" do
    sign_in_as(@admin)
    post "/api/v1/admin/categories", params: { category: { name: "New Category" } }
    assert_response :created
    assert_equal "New Category", Category.find_by(name: "New Category").name
  end

  test "admin can update a category" do
    category = categories(:one)
    sign_in_as(@admin)
    patch "/api/v1/admin/categories/#{category.id}", params: { category: { name: "Updated" } }
    assert_response :success
    assert_equal "Updated", category.reload.name
  end

  test "admin can delete a category without skills" do
    category = Category.create!(name: "Empty Category")
    sign_in_as(@admin)
    delete "/api/v1/admin/categories/#{category.id}"
    assert_response :no_content
    assert_not Category.exists?(category.id)
  end

  test "admin cannot delete a category with skills" do
    category = categories(:one) # skills(:one) belongs to it
    sign_in_as(@admin)
    delete "/api/v1/admin/categories/#{category.id}"
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_match(/contains 1 skill/, body["error"])
    assert Category.exists?(category.id)
  end

  test "validation errors return 422" do
    sign_in_as(@admin)
    post "/api/v1/admin/categories", params: { category: { name: "" } }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "coach cannot access admin categories" do
    sign_in_as(@coach)
    get "/api/v1/admin/categories"
    assert_response :forbidden
  end

  test "player cannot access admin categories" do
    sign_in_as(@player)
    get "/api/v1/admin/categories"
    assert_response :forbidden
  end

  test "unauthenticated cannot access admin categories" do
    get "/api/v1/admin/categories"
    assert_response :unauthorized
  end
end
