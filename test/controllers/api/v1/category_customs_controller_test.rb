require "test_helper"

class Api::V1::CategoryCustomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:three)    # authored the `private_rubric` fixture
    @other_coach = users(:six) # authored `mental_game`, owns no private row of theirs
    @admin = users(:two)
    @curator = users(:four)
    @player_user = users(:one)
    @shared = category_customs(:mental_game)
    @private_row = category_customs(:private_rubric)
  end

  # --- index -----------------------------------------------------------------

  test "index requires authentication" do
    get api_v1_category_customs_path
    assert_response :unauthorized
  end

  test "index refuses a player-role user" do
    sign_in_as(@player_user)
    get api_v1_category_customs_path
    assert_response :forbidden
  end

  test "another coach sees the shared catalogue but not somebody's private row" do
    sign_in_as(@other_coach)
    get api_v1_category_customs_path

    assert_response :success
    names = JSON.parse(response.body).map { |row| row["name"] }
    assert_includes names, "Mental game"
    assert_not_includes names, "Private rubric", "a private row must not leak through the index"
  end

  test "the author sees their own private row" do
    sign_in_as(@owner)
    get api_v1_category_customs_path

    names = JSON.parse(response.body).map { |row| row["name"] }
    assert_includes names, "Private rubric"
  end

  test "oversight sees everything" do
    sign_in_as(@admin)
    get api_v1_category_customs_path

    names = JSON.parse(response.body).map { |row| row["name"] }
    assert_includes names, "Private rubric"
    assert_includes names, "Mental game"
  end

  test "mine narrows the catalogue to the caller's own rows" do
    sign_in_as(@other_coach)
    get api_v1_category_customs_path, params: { mine: "1" }

    rows = JSON.parse(response.body)
    assert_equal [ @shared.id ], rows.map { |row| row["id"] }
  end

  # --- show ------------------------------------------------------------------

  test "show returns a row the caller may use" do
    sign_in_as(@owner)
    get api_v1_category_custom_path(@private_row)

    assert_response :success
    assert_equal "Private rubric", JSON.parse(response.body)["name"]
    assert_equal "private", JSON.parse(response.body)["visibility"]
  end

  test "show is 404, not 403, for a row that is not visible to this caller" do
    sign_in_as(@other_coach)
    get api_v1_category_custom_path(@private_row)

    assert_response :not_found
  end

  # --- create ----------------------------------------------------------------

  test "create stamps provenance and defaults to shared" do
    sign_in_as(@owner)
    assert_difference -> { CategoryCustom.count }, 1 do
      post api_v1_category_customs_path, params: {
        category_custom: { name: "Court sense" }
      }, as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal @owner.id, body["created_by"]["id"]
    assert_equal "shared", body["visibility"]
  end

  test "create refuses a curator, who records no content" do
    sign_in_as(@curator)
    post api_v1_category_customs_path, params: {
      category_custom: { name: "Nope" }
    }, as: :json

    assert_response :forbidden
  end

  test "create refuses a second row with the same name for the same creator" do
    sign_in_as(@other_coach)
    post api_v1_category_customs_path, params: {
      category_custom: { name: @shared.name }
    }, as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join(" "), "already been taken"
  end

  # --- update ----------------------------------------------------------------

  test "the author may edit their own row" do
    sign_in_as(@owner)
    patch api_v1_category_custom_path(@private_row), params: {
      category_custom: { name: "Private rubric v2" }
    }, as: :json

    assert_response :success
    assert_equal "Private rubric v2", @private_row.reload.name
  end

  test "another coach may not edit a row they do not own" do
    sign_in_as(@other_coach)
    patch api_v1_category_custom_path(@private_row), params: {
      category_custom: { name: "Tampered" }
    }, as: :json

    assert_response :not_found, "not even visible, so 404 rather than 403"
    assert_equal "Private rubric", @private_row.reload.name
  end

  test "oversight may edit any visible row" do
    sign_in_as(@admin)
    patch api_v1_category_custom_path(@shared), params: {
      category_custom: { visibility: "private" }
    }, as: :json

    assert_response :success
    assert_equal "private", @shared.reload.visibility
  end
end
