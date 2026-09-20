require "test_helper"

# Private test-access gate: request-level behaviour of the TestAccess concern
# and the Api::V1::TestAccessController endpoints.
class ApiTestAccessTest < ActionDispatch::IntegrationTest
  setup do
    @password = "test-gate-password-123"
    ENV["TEST_ACCESS_PASSWORD"] = @password
    ENV.delete("TEST_ACCESS_TOKEN_EXPIRATION")
  end

  teardown do
    ENV.delete("TEST_ACCESS_PASSWORD")
    ENV.delete("TEST_ACCESS_TOKEN_EXPIRATION")
  end

  test "wrong password is rejected with 401 and no hint" do
    post "/api/v1/test_access", params: { password: "wrong" }, as: :json

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal false, body["authenticated"]
    assert_equal "Invalid password", body["error"]
    assert_nil body["token"]
  end

  test "correct password returns a signed token and expiry" do
    post "/api/v1/test_access", params: { password: @password }, as: :json

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal true, body["authenticated"]
    assert TestAccessToken.valid?(body["token"])
    assert_not_nil body["expires_at"]
    # Default expiration is 7 days.
    assert_in_delta 7.days.from_now.utc.to_i,
                    Time.iso8601(body["expires_at"]).to_i, 5
  end

  test "protected API endpoint rejects requests without the test-access header" do
    get "/api/v1/drills", as: :json

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal false, body["authenticated"]
    assert_equal "test_access_required", body["code"]
  end

  test "protected API endpoint accepts a valid test-access token" do
    token = TestAccessToken.generate
    get "/api/v1/drills", headers: { "X-Test-Access-Token" => token }, as: :json

    assert_response :ok
  end

  test "health index stays public while the gate is enabled" do
    get "/api/v1/health", as: :json

    assert_response :ok
  end

  test "health detailed stays gated by the test-access layer" do
    get "/api/v1/health/detailed", as: :json

    assert_response :unauthorized
  end

  test "tampered token is rejected" do
    token = TestAccessToken.generate
    tampered = "#{token}x"
    get "/api/v1/drills", headers: { "X-Test-Access-Token" => tampered }, as: :json

    assert_response :unauthorized
  end

  test "expired token is rejected" do
    ENV["TEST_ACCESS_TOKEN_EXPIRATION"] = "1.hour"
    post "/api/v1/test_access", params: { password: @password }, as: :json
    token = JSON.parse(response.body)["token"]

    travel 2.hours do
      get "/api/v1/drills", headers: { "X-Test-Access-Token" => token }, as: :json
      assert_response :unauthorized
    end
  end

  test "verification endpoint accepts a valid token and rejects an invalid one" do
    token = TestAccessToken.generate
    get "/api/v1/test_access", headers: { "X-Test-Access-Token" => token }, as: :json
    assert_response :ok
    assert_equal true, JSON.parse(response.body)["authenticated"]

    get "/api/v1/test_access", headers: { "X-Test-Access-Token" => "garbage" }, as: :json
    assert_response :unauthorized
  end

  test "gate is disabled when TEST_ACCESS_PASSWORD is not set" do
    ENV.delete("TEST_ACCESS_PASSWORD")

    # Endpoints work without any token.
    get "/api/v1/drills", as: :json
    assert_response :ok

    # And the create endpoint reports the disabled state.
    post "/api/v1/test_access", params: { password: "anything" }, as: :json
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal true, body["authenticated"]
    assert_equal true, body["disabled"]
    assert_nil body["token"]
  end

  test "test-access create is open even when the gate is enabled" do
    post "/api/v1/test_access", params: { password: @password }, as: :json
    assert_response :ok
  end
end
