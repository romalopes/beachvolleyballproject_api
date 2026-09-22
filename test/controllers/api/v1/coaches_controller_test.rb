require "test_helper"

class Api::V1::CoachesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @public_user = users(:one)
    @trainer = users(:five)
    @admin = users(:four)
  end

  test "index returns all active coaches" do
    sign_in_as(@admin)
    get api_v1_coaches_path
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body
    assert body.any? { |c| c["person"]["first_name"] == "Coach" }
  end

  test "index filters by name search" do
    sign_in_as(@admin)
    get api_v1_coaches_path, params: { q: "Coach" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body.all? { |c| c["full_name"].downcase.include?("coach") }
  end

  test "index filters by email" do
    sign_in_as(@admin)
    get api_v1_coaches_path, params: { email: "coaches@example.com" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body.all? { |c| c["person"]["email"] == "coaches@example.com" }
  end

  test "show returns coach detail" do
    coach = coach_profiles(:carlos_coach)
    sign_in_as(@admin)
    get api_v1_coach_path(coach)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal coach.id, body["id"]
    assert_equal "Carlos", body["person"]["first_name"]
  end

  test "show returns 404 for missing coach" do
    sign_in_as(@admin)
    get api_v1_coach_path(99999)
    assert_response :not_found
  end

  test "create coach requires coach or admin role" do
    sign_in_as(@public_user)
    post api_v1_coaches_path, params: coach_create_params
    assert_response :forbidden
  end

  test "create coach as coach" do
    sign_in_as(@trainer)

    post api_v1_coaches_path, params: coach_create_params

    assert_response :created
    body = JSON.parse(response.body)
    assert_kind_of Integer, body["id"]
    assert_equal "New", body["person"]["first_name"]
    assert body["coach_profile_id"].present?
    assert_equal "Active", body["status"]
  end

  test "create returns validation errors" do
    sign_in_as(@admin)
    post api_v1_coaches_path, params: {
      coach: { person: { first_name: "" }, coach_profile: { coaching_level: "t olympic" } }
    }
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_kind_of Array, body["errors"]
  end

  test "create coach with profile attributes" do
    sign_in_as(@admin)
    count_before = coach_profiles.count
    post api_v1_coaches_path, params: {
      coach: {
        person: { first_name: "NewCoach2", last_name: "User" },
        coach_profile: { coaching_level: "national", qualifications: "USVTT cert" }
      }
    }
    assert_response :created
    assert_equal count_before + 1, coach_profiles.reload.count
  end

  private

  def coach_create_params
    { coach: {
      person: { first_name: "New", last_name: "Coach", email: "new_coach_#{Time.now.to_i}@example.com" },
      coach_profile: { coaching_level: "state", qualifications: "Level 1" }
    } }
  end
end
