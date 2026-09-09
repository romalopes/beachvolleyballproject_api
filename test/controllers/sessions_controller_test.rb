require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "api create with valid credentials returns a bearer token" do
    post "/api/v1/sessions", params: { email_address: @user.email_address, password: "password", api: true }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["token"].present?
    assert_equal @user.id, body["id"]
    assert_nil cookies[:session_id]
  end

  test "api me works with the bearer token" do
    post "/api/v1/sessions", params: { email_address: @user.email_address, password: "password", api: true }, as: :json
    token = JSON.parse(response.body)["token"]

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @user.email_address, body["email_address"]
  end

  test "api me returns 401 without a token" do
    get "/api/v1/me"

    assert_response :unauthorized
  end

  test "api destroy invalidates the token" do
    post "/api/v1/sessions", params: { email_address: @user.email_address, password: "password", api: true }, as: :json
    token = JSON.parse(response.body)["token"]

    delete "/api/v1/sessions", headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_response :success
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unauthorized
  end
end
