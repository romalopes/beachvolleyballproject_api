require "test_helper"

class AdminUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two) # has coach + admin roles
    @player = users(:one) # has player role
  end

  test "admin can list users" do
    sign_in_as(@admin)
    get "/api/v1/admin/users"
    assert_response :success
    body = JSON.parse(response.body)
    assert body["data"].any? { |u| u["email_address"] == @admin.email_address }
  end

  test "admin can view a user with account details" do
    account = @player.create_account!(first_name: "Bea", last_name: "Volley", email: @player.email_address)
    account.create_account_address!(city: "Copacabana", country: "BR")

    sign_in_as(@admin)
    get "/api/v1/admin/users/#{@player.id}"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @player.id, body["id"]
    assert_equal @player.email_address, body["email_address"]
    assert_equal account.id, body["account_id"]
    assert_equal "Bea", body["account"]["first_name"]
    assert_equal "Volley", body["account"]["last_name"]
    assert_equal "Copacabana", body["account"]["address"]["city"]
    assert body["roles"].any? { |role| role["name"] == "player" }
  end

  test "non-admin cannot view a user" do
    sign_in_as(@player)
    get "/api/v1/admin/users/#{@admin.id}"
    assert_response :forbidden
  end

  test "non-admin cannot list users" do
    sign_in_as(@player)
    get "/api/v1/admin/users"
    assert_response :forbidden
  end

  test "unauthenticated cannot list users" do
    get "/api/v1/admin/users"
    assert_response :unauthorized
  end

  test "admin can add a role to a user" do
    sign_in_as(@admin)
    post "/api/v1/admin/users/#{@player.id}/roles", params: { role: "coach" }
    assert_response :success
    assert @player.reload.coach?
  end

  test "non-admin cannot add a role" do
    sign_in_as(@player)
    post "/api/v1/admin/users/#{@player.id}/roles", params: { role: "admin" }
    assert_response :forbidden
    assert_not @player.reload.admin?
  end

  test "admin cannot remove the last admin" do
    sign_in_as(@admin)
    # @admin is the only admin (users(:two) has admin role)
    delete "/api/v1/admin/users/#{@admin.id}/roles/admin"
    assert_response :unprocessable_entity
    assert @admin.reload.admin?
  end
end
