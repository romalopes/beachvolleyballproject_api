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
end
