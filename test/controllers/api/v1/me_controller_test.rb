require "test_helper"

class Api::V1::MeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one) # player role only
  end

  test "returns the current user with roles when signed in via cookie session" do
    sign_in_as(@user)
    get "/api/v1/me"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @user.id, body["id"]
    assert_equal "User One", body["name"]
    assert_equal "one@example.com", body["email_address"]
    assert_includes body["roles"], "player"
  end

  test "returns the current user when authenticating with a bearer token" do
    session = @user.sessions.create!(
      api_token: SecureRandom.hex(32),
      api_token_expires_at: 30.days.from_now
    )
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{session.api_token}" }
    assert_response :success
    assert_equal @user.id, JSON.parse(response.body)["id"]
  end

  test "rejects an expired bearer token" do
    session = @user.sessions.create!(
      api_token: SecureRandom.hex(32),
      api_token_expires_at: 1.hour.ago
    )
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{session.api_token}" }
    assert_response :unauthorized
  end

  test "returns 401 when unauthenticated" do
    get "/api/v1/me"
    assert_response :unauthorized
  end

  test "exposes the profile ids the SPA defaults the assessor from" do
    sign_in_as(users(:six)) # account two -> person two -> coach profile maria_coach
    get "/api/v1/me"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal people(:two).id, body["person_id"]
    assert_equal coach_profiles(:maria_coach).id, body["coach_profile_id"]
    assert_equal [ coach_profiles(:maria_coach).id ], body["coach_profile_ids"]
    assert_equal [ coach_profiles(:maria_coach).id ], body["coach_profiles"].map { |profile| profile["id"] }
    assert_nil body["player_profile_id"]
  end

  test "returns every coach profile and keeps the first active one as the legacy default" do
    person = people(:two)
    second = CoachProfile.create!(
      person: person,
      coaching_level: "advanced",
      qualifications: "Beach coaching",
      created_by: users(:three)
    )
    sign_in_as(users(:six))

    get "/api/v1/me"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ coach_profiles(:maria_coach).id, second.id ], body["coach_profile_ids"]
    assert_equal [ coach_profiles(:maria_coach).id, second.id ], body["coach_profiles"].map { |profile| profile["id"] }
    assert_equal coach_profiles(:maria_coach).id, body["coach_profile_id"]
  end

  test "returns the caller's account, all player profiles, and organisation/group memberships" do
    person = people(:two)
    second_player = PlayerProfile.create!(person: person, status: "active", preferred_position: "setter")
    sign_in_as(users(:six))

    get "/api/v1/me"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal accounts(:two).id, body["account_id"]
    assert_equal [second_player.id], body["player_profile_ids"]
    assert_equal [second_player.id], body["player_profiles"].map { |profile| profile["id"] }
    assert_includes body["organisation_memberships"].map { |membership| membership["organisation_id"] },
                    organisations(:sydney_club).id
    assert_includes body["organisation_memberships"].map { |membership| membership["organisation_id"] },
                    organisations(:sydney_academy).id
    membership = body["group_memberships"].find { |row| row["group_id"] == groups(:u19_squad).id }
    assert_equal "owner", membership["role"]
    assert_equal "U19 squad", membership.dig("group", "name")
  end

  test "does not return another user's context when the authenticated user has no Person" do
    sign_in_as(users(:two))

    get "/api/v1/me"

    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body["person_id"]
    assert_nil body["account_id"]
    assert_equal [], body["player_profiles"]
    assert_equal [], body["coach_profiles"]
    assert_equal [], body["organisation_memberships"]
    assert_equal [], body["group_memberships"]
  end

  test "returns no coach context when the Person has no CoachProfiles" do
    sign_in_as(users(:one))

    get "/api/v1/me"

    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body["coach_profile_id"]
    assert_equal [], body["coach_profile_ids"]
    assert_equal [], body["coach_profiles"]
  end
end
