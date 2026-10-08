require "test_helper"

class Api::V1::CoachesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @public_user = users(:one)
    @trainer = users(:three)
    @other_coach = users(:six)
    @admin = users(:two)
    @curator = users(:four)
  end

  test "index returns active coach profiles" do
    sign_in_as(@admin)
    get api_v1_coaches_path
    assert_response :success
    rows = JSON.parse(response.body).fetch("data")
    assert_includes rows.map { |row| row.fetch("id") }, coach_profiles(:maria_coach).id
    assert rows.all? { |row| row.key?("coach_profile_id") }
  end

  test "index paginates profile records" do
    sign_in_as(@admin)
    baseline = CoachProfile.count
    22.times { |index| CoachProfile.create!(display_name: "Coach #{format('%02d', index)}") }

    get api_v1_coaches_path
    first = JSON.parse(response.body)
    assert_equal 20, first.fetch("data").length
    assert_equal baseline + 22, first.dig("meta", "total")

    get api_v1_coaches_path, params: { page: 2 }
    second = JSON.parse(response.body)
    assert_empty first.fetch("data").map { |row| row.fetch("id") } & second.fetch("data").map { |row| row.fetch("id") }
  end

  test "create requires manager and stamps creator account" do
    sign_in_as(@public_user)
    post api_v1_coaches_path, params: coach_create_params
    assert_response :forbidden

    sign_out
    sign_in_as(@trainer)
    post api_v1_coaches_path, params: coach_create_params
    assert_response :created
    profile = CoachProfile.find(JSON.parse(response.body).fetch("id"))
    assert_equal "New Coach", profile.display_name
    assert_equal "new.coach@example.com", profile.email
    assert_nil profile.account_id
    assert_equal accounts(:three).id, profile.created_by_account_id
  end

  test "client supplied ownership fields are ignored" do
    sign_in_as(@trainer)
    post api_v1_coaches_path, params: {
      coach: { coach_profile: { display_name: "Untrusted Coach", account_id: accounts(:one).id, created_by_account_id: accounts(:one).id } }
    }
    assert_response :created
    profile = CoachProfile.find(JSON.parse(response.body).fetch("id"))
    assert_nil profile.account_id
    assert_equal accounts(:three).id, profile.created_by_account_id
  end

  test "invalid profile attributes return validation errors" do
    sign_in_as(@admin)
    post api_v1_coaches_path, params: { coach: { coach_profile: { display_name: "" } } }
    assert_response :unprocessable_entity

    patch api_v1_coach_path(coach_profiles(:maria_coach)), params: { coach: { coach_profile: { visibility: "bogus" } } }
    assert_response :unprocessable_entity
  end

  test "show and update use coach profile attributes" do
    coach = coach_profiles(:maria_coach)
    sign_in_as(@admin)
    get api_v1_coach_path(coach)
    assert_response :success
    assert_equal coach.id, JSON.parse(response.body).fetch("id")

    patch api_v1_coach_path(coach), params: { coach: { coach_profile: { coaching_level: "national", qualifications: "Level 3", email: "coach@example.com" } } }
    assert_response :success
    assert_equal "national", JSON.parse(response.body).fetch("coaching_level")
    assert_equal "coach@example.com", JSON.parse(response.body).fetch("email")
    assert_equal "Level 3", coach.reload.qualifications
    assert_equal "coach@example.com", coach.email
  end

  test "private coaches are hidden from unrelated coaches but visible to owner and curator" do
    private_coach = private_coach_owned_by(@trainer)
    sign_in_as(@other_coach)
    get api_v1_coaches_path
    assert_not_includes JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }, private_coach.id
    get api_v1_coach_path(private_coach)
    assert_response :not_found

    sign_out
    sign_in_as(@trainer)
    get api_v1_coach_path(private_coach)
    assert_response :success

    sign_out
    sign_in_as(@curator)
    get api_v1_coach_path(private_coach)
    assert_response :success
  end

  test "only owner or admin can flip visibility" do
    private_coach = private_coach_owned_by(@trainer)
    sign_in_as(@other_coach)
    patch api_v1_coach_path(private_coach), params: { coach: { coach_profile: { visibility: "shared" } } }
    assert_response :not_found

    private_coach.update!(visibility: "shared")
    patch api_v1_coach_path(private_coach), params: { coach: { coach_profile: { visibility: "private" } } }
    assert_response :forbidden

    sign_out
    sign_in_as(@trainer)
    patch api_v1_coach_path(private_coach), params: { coach: { coach_profile: { visibility: "private" } } }
    assert_response :success

    sign_out
    sign_in_as(@admin)
    patch api_v1_coach_path(private_coach), params: { coach: { coach_profile: { visibility: "shared" } } }
    assert_response :success
  end

  test "status filter exposes archived profiles on request" do
    sign_in_as(@admin)
    coach = coach_profiles(:maria_coach)
    coach.update!(status: "archived")
    get api_v1_coaches_path
    assert_not_includes JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }, coach.id
    get api_v1_coaches_path, params: { status: "archived" }
    assert_includes JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }, coach.id
  end

  test "admin can delete unused coach profile without deleting account" do
    coach = CoachProfile.create!(display_name: "Connected coach", account: accounts(:two))
    account = coach.account
    sign_in_as(@admin)
    delete api_v1_coach_path(coach)
    assert_response :no_content
    assert_not CoachProfile.exists?(coach.id)
    assert Account.exists?(account.id)
  end

  test "show exposes coach assessment attribution" do
    sign_in_as(@admin)
    get api_v1_coach_path(coach_profiles(:maria_coach))
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.fetch("assessments_recorded_count")
    assert_equal [ assessments(:skill_active).id ], body.fetch("recent_assessments").map { |row| row.fetch("id") }
  end

  private

  def private_coach_owned_by(owner)
    profile = CoachProfile.new(display_name: "Quiet Coach", visibility: "private", created_by: owner)
    ProfileOwnership.stamp!(profile, owner)
    profile.save!
    profile
  end

  def coach_create_params
    { coach: { coach_profile: { display_name: "New Coach", email: "new.coach@example.com", coaching_level: "state", qualifications: "Level 1" } } }
  end
end