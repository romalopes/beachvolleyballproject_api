require "test_helper"

class Api::V1::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "registers a new user with a cookie session by default" do
    assert_difference([ "User.count", "Account.count", "ContactDetail.count" ]) do
      post "/api/v1/registrations", params: { user: {
        name: "New Player",
        email_address: "newbie@example.com",
        password: "password123",
        password_confirmation: "password123"
      } }
    end
    # With email verification required (the default in test env), registration
    # returns a pending state. The verification secret is delivered by email,
    # never returned to the unauthenticated registration caller.
    assert_response :accepted
    body = JSON.parse(response.body)
    assert_equal "newbie@example.com", body["email_address"]
    assert_includes body["roles"], "player"
    assert_nil body["verification_token"]
    assert_equal "pending_verification", body["status"]
    account = User.find(body.fetch("id")).account
    assert account
    assert_equal "New", account.contact_detail.first_name
    assert_equal "newbie@example.com", account.contact_detail.email
  end

  test "registers a new user and returns pending_verification even with api=true" do
    # Regression: the API-grant branch previously bypassed email verification
    # entirely, letting unverified signups straight in with a session token.
    assert_difference([ "User.count", "Account.count", "ContactDetail.count" ]) do
      assert_no_difference("Session.count") do
        post "/api/v1/registrations", params: {
          user: {
            name: "API Player",
            email_address: "apiplayer@example.com",
            password: "password123",
            password_confirmation: "password123"
          },
          api: true
        }
      end
    end
    assert_response :accepted
    body = JSON.parse(response.body)
    assert_equal "pending_verification", body["status"]
    assert_nil body["token"]
    assert_nil body["verification_token"]
  end

  test "verification is skipped when verification is not required" do
    # With the feature toggled off, api=true signup returns a real session
    # token as before.
    prev = ENV["REQUIRE_EMAIL_VERIFICATION"]
    ENV["REQUIRE_EMAIL_VERIFICATION"] = "false"
    begin
      assert_difference([ "User.count", "Account.count", "ContactDetail.count", "Session.count" ]) do
        post "/api/v1/registrations", params: {
          user: {
            name: "Token Check",
            email_address: "tokencheck@example.com",
            password: "password123",
            password_confirmation: "password123"
          },
          api: true
        }
      end
    ensure
      if prev.nil?
        ENV.delete("REQUIRE_EMAIL_VERIFICATION")
      else
        ENV["REQUIRE_EMAIL_VERIFICATION"] = prev
      end
    end
    assert_response :created
    body = JSON.parse(response.body)
    token = body["token"]
    assert_not_nil token
    assert_includes body["roles"], "player"

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
    assert_equal "tokencheck@example.com", JSON.parse(response.body)["email_address"]
  end

  test "returns 422 when the email is already taken" do
    assert_no_difference("User.count") do
      post "/api/v1/registrations", params: { user: {
        name: "Dupe",
        email_address: "one@example.com",
        password: "password123",
        password_confirmation: "password123"
      } }
    end
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "returns 422 when the password is too short" do
    post "/api/v1/registrations", params: { user: {
      name: "Shorty",
      email_address: "shorty@example.com",
      password: "short",
      password_confirmation: "short"
    } }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "returns 422 when password confirmation does not match" do
    post "/api/v1/registrations", params: { user: {
      name: "Mismatch",
      email_address: "mismatch@example.com",
      password: "password123",
      password_confirmation: "different123"
    } }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end
end
