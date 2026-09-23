require "test_helper"

# Request tests for the identity search used by the "create player/coach" flow.
#
# The endpoint answers "has this human already been recorded?" before a new
# Person is created, so it exposes contact details and is therefore staff-only
# (coaches/admins — the same people who may create profiles).
class Api::V1::PeopleControllerTest < ActionDispatch::IntegrationTest
  setup do
    @public_user = users(:one)   # player role only
    @trainer = users(:three)     # coach role only
    @admin = users(:two)         # coach + admin
    @curator = users(:four)      # curator: manages trainings, not content
  end

  test "index lists canonical people with account status and profile ids" do
    sign_in_as(@admin)
    get api_v1_people_path

    assert_response :success
    body = JSON.parse(response.body)

    john = body.find { |person| person["id"] == people(:one).id }
    assert_equal "John Smith", john["full_name"]
    assert_equal "connected", john["account_status"]
    assert_equal player_profiles(:john_player).id, john["player_profile_id"]
    assert_nil john["coach_profile_id"]

    pedro = body.find { |person| person["id"] == people(:accountless_player).id }
    assert_equal "profile_only", pedro["account_status"]
    assert_equal player_profiles(:pedro_player).id, pedro["player_profile_id"]
  end

  test "index excludes merged people" do
    sign_in_as(@admin)
    get api_v1_people_path

    ids = JSON.parse(response.body).map { |person| person["id"] }
    assert_not_includes ids, people(:merged).id
  end

  test "index orders people by last name then first name" do
    sign_in_as(@admin)
    get api_v1_people_path

    keys = JSON.parse(response.body).map { |p| [ p["last_name"].to_s, p["first_name"].to_s, p["id"] ] }
    assert_equal keys.sort, keys
  end

  test "index searches by name or email" do
    sign_in_as(@admin)
    get api_v1_people_path, params: { q: "Pedro" }

    assert_response :success
    names = JSON.parse(response.body).map { |person| person["full_name"] }
    assert_equal [ "Pedro Santos" ], names

    get api_v1_people_path, params: { q: "one@example.com" }
    emails = JSON.parse(response.body).map { |person| person["email"] }
    assert_includes emails, "one@example.com"
  end

  test "index filters by exact email" do
    sign_in_as(@admin)
    get api_v1_people_path, params: { email: "ONE@example.com" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ people(:one).id ], body.map { |person| person["id"] }
  end

  test "index finds a person by a previous name" do
    sign_in_as(@admin)

    get api_v1_people_path, params: { q: "Johnny" }

    assert_response :success
    ids = JSON.parse(response.body).map { |person| person["id"] }
    assert_equal [ people(:one).id ], ids
  end

  test "index returns the alternate names with each person" do
    sign_in_as(@admin)

    get api_v1_people_path, params: { q: "one@example.com" }

    body = JSON.parse(response.body)
    assert_equal %w[Johnny\ Smith João\ Smith].sort, body.first["aliases"].sort
  end

  test "index is limited so it cannot dump the whole people table" do
    sign_in_as(@admin)
    (Api::V1::PeopleController::LIMIT + 5).times do |index|
      Person.create!(first_name: "Person#{index}", last_name: "Zzz", creation_source: "system")
    end

    get api_v1_people_path

    assert_response :success
    assert_equal Api::V1::PeopleController::LIMIT, JSON.parse(response.body).length
  end

  test "index requires a content creator" do
    [ @public_user, @curator ].each do |viewer|
      sign_in_as(viewer)
      get api_v1_people_path
      assert_response :forbidden
    end
  end

  test "index requires authentication" do
    get api_v1_people_path
    assert_response :unauthorized
  end
end
