require "test_helper"

class Api::V1::CategoriesControllerTest < ActionDispatch::IntegrationTest
  test "index is public" do
    get "/api/v1/categories"
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body
    assert body.any? { |c| c["slug"] == "mystring-one" }
  end

  test "show is public" do
    get "/api/v1/categories/mystring-one"
    assert_response :success
    assert_equal "mystring-one", JSON.parse(response.body)["slug"]
  end

  test "show falls back to lookup by id" do
    category = categories(:one)
    get "/api/v1/categories/#{category.id}"
    assert_response :success
    assert_equal category.id, JSON.parse(response.body)["id"]
  end

  test "create works without authentication" do
    assert_difference("Category.count") do
      post "/api/v1/categories", params: { category: { name: "Brand New" } }
    end
    assert_response :created
    assert_equal "brand-new", Category.find_by(name: "Brand New").slug
  end

  test "create returns 422 on validation errors" do
    post "/api/v1/categories", params: { category: { name: "" } }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "update renames the category" do
    category = categories(:one)
    patch "/api/v1/categories/#{category.slug}", params: { category: { name: "Renamed Category" } }
    assert_response :success
    assert_equal "Renamed Category", category.reload.name
  end

  test "update returns 422 on validation errors" do
    category = categories(:one)
    patch "/api/v1/categories/#{category.slug}", params: { category: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "destroy deletes the category" do
    category = Category.create!(name: "Disposable")
    assert_difference("Category.count", -1) do
      delete "/api/v1/categories/#{category.slug}"
    end
    assert_response :no_content
  end

  test "destroy cascades to its skills" do
    category = Category.create!(name: "With Skills")
    Skill.create!(title: "Child", category: category)
    assert_difference("Category.count", -1) do
      assert_difference("Skill.count", -1) do
        delete "/api/v1/categories/#{category.slug}"
      end
    end
    assert_response :no_content
  end
end
