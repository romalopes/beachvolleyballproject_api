require "test_helper"

class Api::V1::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "registers a new user with a cookie session by default" do
    assert_difference(["User.count", "Session.count"]) do
      post "/api/v1/registrations", params: { user: {
        name: "New Player",
        email_address: "newbie@example.com",
        password: "password123",
        password_confirmation: "password123"
      } }
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "newbie@example.com", body["email_address"]
    assert_includes body["roles"], "player"
    assert_nil body["token"]
  end

  test "registers a new user and returns an API token when api=true" do
    assert_difference(["User.count", "Session.count"]) do
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
    assert_response :created
    body = JSON.parse(response.body)
    assert_not_nil body["token"]
    assert_includes body["roles"], "player"
  end

  test "token returned at registration authenticates the bearer session" do
    post "/api/v1/registrations", params: {
      user: {
        name: "Token Check",
        email_address: "tokencheck@example.com",
        password: "password123",
        password_confirmation: "password123"
      },
      api: true
    }
    token = JSON.parse(response.body)["token"]
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
