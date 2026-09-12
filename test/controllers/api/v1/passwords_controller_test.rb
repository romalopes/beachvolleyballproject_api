require "test_helper"

class Api::V1::PasswordsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "create returns 204 even when the email is unknown (no enumeration)" do
    post "/api/v1/passwords", params: { email_address: "nobody@example.com" }
    assert_response :no_content
    assert_no_enqueued_emails
  end

  test "create enqueues a reset email for a known user" do
    assert_enqueued_email_with PasswordsMailer, :reset, args: [users(:one)] do
      post "/api/v1/passwords", params: { email_address: "one@example.com" }
    end
    assert_response :no_content
  end

  test "update sets a new password with a valid token" do
    user = users(:one)
    put "/api/v1/passwords/#{user.password_reset_token}", params: {
      password: "brandnewpassword",
      password_confirmation: "brandnewpassword"
    }
    assert_response :no_content
    assert user.reload.authenticate("brandnewpassword")
  end

  test "update terminates all sessions after a password reset" do
    user = users(:one)
    user.sessions.create!
    put "/api/v1/passwords/#{user.password_reset_token}", params: {
      password: "brandnewpassword",
      password_confirmation: "brandnewpassword"
    }
    assert_response :no_content
    assert_empty user.reload.sessions
  end

  test "update returns 422 when the confirmation does not match" do
    user = users(:one)
    put "/api/v1/passwords/#{user.password_reset_token}", params: {
      password: "brandnewpassword",
      password_confirmation: "somethingelse"
    }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "update returns 422 for an invalid or expired token" do
    put "/api/v1/passwords/invalid-token", params: {
      password: "brandnewpassword",
      password_confirmation: "brandnewpassword"
    }
    assert_response :unprocessable_entity
    assert_equal "Password reset link is invalid or has expired.", JSON.parse(response.body)["error"]
  end
end
