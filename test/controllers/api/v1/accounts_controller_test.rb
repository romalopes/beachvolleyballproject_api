require "test_helper"

class Api::V1::AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "show returns a blank account payload when none exists" do
    sign_in_as(@user)
    get "/api/v1/account"
    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body["id"]
    assert_nil body["first_name"]
    assert_equal(
      { "street_address" => nil, "city" => nil, "state" => nil, "postal_code" => nil, "country" => nil },
      body["address"]
    )
  end

  test "show returns the existing account with its address" do
    account = @user.create_account!(first_name: "Bea", last_name: "Volley")
    account.create_account_address!(city: "Copacabana", country: "BR")
    sign_in_as(@user)
    get "/api/v1/account"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal account.id, body["id"]
    assert_equal "Bea", body["first_name"]
    assert_equal "Copacabana", body["address"]["city"]
  end

  test "show requires authentication" do
    get "/api/v1/account"
    assert_response :unauthorized
  end

  test "update creates the account with a nested address" do
    sign_in_as(@user)
    patch "/api/v1/account", params: {
      first_name: "Bea",
      last_name: "Volley",
      phone: "+55 21 99999-0000",
      address: { street_address: "Av. Atlântica 100", city: "Rio", state: "RJ", postal_code: "22010", country: "BR" }
    }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Bea", body["first_name"]
    assert_equal "Rio", body["address"]["city"]
    assert_equal "Bea", @user.reload.account.first_name
  end

  test "update returns 422 when the date of birth is in the future" do
    sign_in_as(@user)
    patch "/api/v1/account", params: { first_name: "Bea", date_of_birth: 1.day.from_now.to_date.to_s }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "update requires authentication" do
    patch "/api/v1/account", params: { first_name: "Bea" }
    assert_response :unauthorized
  end

  test "update_password changes the password with the correct current password" do
    sign_in_as(@user)
    other_session = @user.sessions.create!
    patch "/api/v1/account/password", params: {
      current_password: "password",
      password: "newpassword123",
      password_confirmation: "newpassword123"
    }
    assert_response :success
    assert_equal "Password changed successfully.", JSON.parse(response.body)["message"]
    assert @user.reload.authenticate("newpassword123")
    assert_not Session.exists?(other_session.id), "other sessions should be revoked"
  end

  test "update_password rejects a wrong current password" do
    sign_in_as(@user)
    patch "/api/v1/account/password", params: {
      current_password: "wrong",
      password: "newpassword123",
      password_confirmation: "newpassword123"
    }
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Current password is incorrect."
  end

  test "update_password rejects a short password" do
    sign_in_as(@user)
    patch "/api/v1/account/password", params: {
      current_password: "password",
      password: "short",
      password_confirmation: "short"
    }
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Password must be at least 8 characters."
  end

  test "update_password rejects a mismatched confirmation" do
    sign_in_as(@user)
    patch "/api/v1/account/password", params: {
      current_password: "password",
      password: "newpassword123",
      password_confirmation: "different123"
    }
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Password confirmation does not match."
  end

  test "update_password requires authentication" do
    patch "/api/v1/account/password", params: {
      current_password: "password",
      password: "newpassword123",
      password_confirmation: "newpassword123"
    }
    assert_response :unauthorized
  end
end
