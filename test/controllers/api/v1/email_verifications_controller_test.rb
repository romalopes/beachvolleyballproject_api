require "test_helper"

class Api::V1::EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      name: "Verify Me",
      email_address: "verifyme@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @raw_token = @user.generate_email_verification_token!
  end

  test "verification endpoint is reachable without authentication" do
    # Regression: the controller previously required a session, which an
    # unverified user by definition does not have — every click returned 401.
    get "/api/v1/email-verifications/#{@raw_token}"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "verified", body["status"]
    assert_equal "verifyme@example.com", body["email_address"]
    assert @user.reload.email_verified?
  end

  test "token is single-use" do
    get "/api/v1/email-verifications/#{@raw_token}"
    assert_response :success
    get "/api/v1/email-verifications/#{@raw_token}"
    assert_response :unprocessable_entity
  end

  test "invalid token returns 422 without authentication" do
    get "/api/v1/email-verifications/not-a-real-token"
    assert_response :unprocessable_entity
  end
end
