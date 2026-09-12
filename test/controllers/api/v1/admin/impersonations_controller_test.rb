require "test_helper"

class Api::V1::Admin::ImpersonationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)    # coach + admin
    @coach = users(:three)  # coach role only
    @player = users(:one)   # player role only
  end

  # 1. Admin can start impersonating a normal user.
  test "admin can start impersonating a normal user" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: @player.id }
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal true, body["impersonating"]
    assert_equal @player.id, body["effective_user"]["id"]
    assert_equal @admin.id, body["real_admin"]["id"]
  end

  # 2. Normal user cannot start impersonating another user.
  test "normal user cannot start impersonating" do
    sign_in_as(@player)
    post "/api/v1/admin/impersonations", params: { user_id: @coach.id }
    assert_response :forbidden
    get "/api/v1/me"
    assert_equal @player.id, JSON.parse(response.body)["id"]
    assert_nil JSON.parse(response.body)["impersonating"]
  end

  test "guest cannot start impersonating" do
    post "/api/v1/admin/impersonations", params: { user_id: @player.id }
    assert_response :unauthorized
  end

  # 3 + 4. current_user is the impersonated user; real_current_user is admin.
  test "current_user is impersonated user and real user stays admin" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: @player.id }
    assert_response :created
    get "/api/v1/me"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @player.id, body["id"]
    assert_equal true, body["impersonating"]
    assert_equal @admin.id, body["real_admin"]["id"]
    assert_equal @admin.email_address, body["real_admin"]["email_address"]
  end

  # 5. A drill created during impersonation belongs to the impersonated user.
  test "records created while impersonating belong to impersonated user" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: @coach.id }
    assert_response :created
    post "/api/v1/drills", params: { drill: {
      title: "Impersonated Drill",
      training_stage: "warmup", difficulty_level: "beginner",
      min_players: 2, max_players: 4, ideal_num_players: 2
    } }
    assert_response :created
    assert_equal @coach.id, Drill.find_by(title: "Impersonated Drill").created_by_id
  end

  # 6. A drill created normally still belongs to the real logged-in user.
  test "records created normally belong to the real user" do
    sign_in_as(@coach)
    post "/api/v1/drills", params: { drill: {
      title: "Own Drill",
      training_stage: "warmup", difficulty_level: "beginner",
      min_players: 2, max_players: 4, ideal_num_players: 2
    } }
    assert_response :created
    assert_equal @coach.id, Drill.find_by(title: "Own Drill").created_by_id
  end

  # 7 + 8. Stop returns to the admin.
  test "admin can stop impersonation and current_user returns to admin" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: @player.id }
    assert_response :created
    delete "/api/v1/admin/impersonations"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["impersonating"]
    assert_nil body["effective_user"]
    get "/api/v1/me"
    assert_response :success
    stop_body = JSON.parse(response.body)
    assert_equal @admin.id, stop_body["id"]
    assert_nil stop_body["impersonating"]
  end

  test "stop without active impersonation returns 422" do
    sign_in_as(@admin)
    delete "/api/v1/admin/impersonations"
    assert_response :unprocessable_entity
  end

  # 9. Impersonation persists across requests.
  test "impersonation persists across requests" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: @player.id }
    assert_response :created
    get "/api/v1/me"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @player.id, body["id"]
    assert_equal true, body["impersonating"]
    assert_equal @admin.id, body["real_admin"]["id"]
  end

  test "impersonation persists across requests via bearer token" do
    post "/api/v1/sessions", params: { email_address: "two@example.com", password: "password", api: true }
    token = JSON.parse(response.body)["token"]
    auth = { "Authorization" => "Bearer #{token}" }
    post "/api/v1/admin/impersonations", headers: auth, params: { user_id: @player.id }
    assert_response :created
    get "/api/v1/me", headers: auth
    assert_response :success
    assert_equal @player.id, JSON.parse(response.body)["id"]
  end

  # 10. Nested impersonation is prevented.
  test "nested impersonation is prevented" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: @player.id }
    assert_response :created
    post "/api/v1/admin/impersonations", params: { user_id: @coach.id }
    assert_response :unprocessable_entity
    get "/api/v1/me"
    assert_equal @player.id, JSON.parse(response.body)["id"]
    assert_equal true, JSON.parse(response.body)["impersonating"]
  end

  test "impersonating a second admin is not allowed" do
    other_admin = User.create!(name: "Other Admin", email_address: "otheradmin@example.com",
                               password: "password123", password_confirmation: "password123")
    other_admin.add_role(:admin)
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: other_admin.id }
    assert_response :unprocessable_entity
    get "/api/v1/me"
    assert_equal @admin.id, JSON.parse(response.body)["id"]
    assert_nil JSON.parse(response.body)["impersonating"]
  end

  test "impersonating yourself is not allowed" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: @admin.id }
    assert_response :unprocessable_entity
    get "/api/v1/me"
    assert_equal @admin.id, JSON.parse(response.body)["id"]
    assert_nil JSON.parse(response.body)["impersonating"]
  end

  test "impersonating an unknown user returns 404" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: 0 }
    assert_response :not_found
    assert_not Current.impersonating?
  end

  # 11. Manual session tampering cannot escalate.
  test "non-admin cannot benefit from direct session tampering" do
    sign_in_as(@player)
    post "/api/v1/admin/impersonations", params: { user_id: @coach.id }
    assert_response :forbidden
    get "/api/v1/me"
    assert_equal @player.id, JSON.parse(response.body)["id"]
    assert_nil JSON.parse(response.body)["impersonating"]
  end

  test "tampered impersonated_user_id on a non-admin session is cleared" do
    sign_in_as(@player)
    Current.session.update!(impersonated_user: @coach)
    get "/api/v1/me"
    assert_response :success
    assert_equal @player.id, JSON.parse(response.body)["id"]
    assert_nil JSON.parse(response.body)["impersonating"]
    assert_nil Current.session.reload.impersonated_user_id
  end

  # 12. Audit logs identify real admin and effective user.
  test "start and stop write audit logs with admin actor and target" do
    sign_in_as(@admin)
    assert_difference("Log.count", 2) do
      post "/api/v1/admin/impersonations", params: { user_id: @player.id }
      delete "/api/v1/admin/impersonations"
    end
    started = Log.order(:created_at).last(2).first
    stopped = Log.order(:created_at).last
    assert_equal @admin.id, started.user_id
    assert_equal "impersonate", started.action
    assert_match(/started acting as/, started.description)
    assert_includes started.log_objects.map(&:object), @player
    assert_equal @admin.id, stopped.user_id
    assert_match(/stopped acting as/, stopped.description)
    assert_includes stopped.log_objects.map(&:object), @player
  end

  # 13. API requests respect impersonation (effective user for ownership).
  test "api requests resolve current_user to the impersonated user" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: @player.id }
    assert_response :created
    # Player is not a content creator: effective permissions apply, so
    # creating a skill is forbidden (an admin could do it).
    post "/api/v1/skills", params: { skill: { title: "Nope", category_id: categories(:one).id } }
    assert_response :forbidden
  end

  # 14. Admin-only functionality stays available while impersonating.
  test "admin endpoints remain available while impersonating" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: @player.id }
    assert_response :created
    get "/api/v1/admin/skills"
    assert_response :success
    get "/api/v1/health/detailed"
    assert_response :success
  end

  test "logout clears impersonation state" do
    sign_in_as(@admin)
    post "/api/v1/admin/impersonations", params: { user_id: @player.id }
    assert_response :created
    delete "/api/v1/sessions"
    assert_response :no_content
    get "/api/v1/me"
    assert_response :unauthorized
  end
end

