require "test_helper"

class Api::V1::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "logs in with valid credentials and starts a cookie session" do
    post "/api/v1/sessions", params: { email_address: "one@example.com", password: "password" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "one@example.com", body["email_address"]
    assert_includes body["roles"], "player"
    assert_nil body["token"]
  end

  test "logs in with api=true and returns a bearer token" do
    post "/api/v1/sessions", params: { email_address: "one@example.com", password: "password", api: true }
    assert_response :success
    token = JSON.parse(response.body)["token"]
    assert_not_nil token

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
    assert_equal "one@example.com", JSON.parse(response.body)["email_address"]
  end

  test "rejects invalid credentials with 401" do
    post "/api/v1/sessions", params: { email_address: "one@example.com", password: "wrongpassword" }
    assert_response :unauthorized
    assert_equal "Invalid email address or password.", JSON.parse(response.body)["error"]
  end

  test "rejects an unknown email with 401" do
    post "/api/v1/sessions", params: { email_address: "nobody@example.com", password: "password" }
    assert_response :unauthorized
  end

  test "records an auth log entry on login" do
    assert_difference("Log.count") do
      post "/api/v1/sessions", params: { email_address: "one@example.com", password: "password" }
    end
    assert_response :success
  end

  test "records an auth log entry on a failed login" do
    assert_difference("Log.count") do
      post "/api/v1/sessions", params: { email_address: "one@example.com", password: "wrongpassword" }
    end
    assert_response :unauthorized
  end

  test "logout destroys the cookie session" do
    user = users(:one)
    sign_in_as(user)
    assert_difference("Session.count", -1) do
      delete "/api/v1/sessions"
    end
    assert_response :no_content
  end

  test "logout destroys a bearer-token session" do
    session = users(:one).sessions.create!(
      api_token: SecureRandom.hex(32),
      api_token_expires_at: 30.days.from_now
    )
    assert_difference("Session.count", -1) do
      delete "/api/v1/sessions", headers: { "Authorization" => "Bearer #{session.api_token}" }
    end
    assert_response :no_content
  end

  test "logout without a session still returns 204" do
    delete "/api/v1/sessions"
    assert_response :no_content
  end
end
