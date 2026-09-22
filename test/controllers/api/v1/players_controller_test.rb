require "test_helper"

class Api::V1::PlayersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @public_user = users(:one)
    @trainer = users(:five)
    @admin = users(:four)
  end

  test "index returns all active players" do
    sign_in_as(@admin)
    get api_v1_players_path
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body
    player_ids = body.map { |p| p["id"] }
    assert_includes player_ids, player_profiles(:john_player).id
    assert player_ids.sort == player_ids, "ordered by last_name, first_name, id"
  end

  test "index filters by name search" do
    sign_in_as(@admin)
    get api_v1_players_path, params: { q: "John" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body.all? { |p| p["full_name"].downcase.include?("john") }
  end

  test "index filters by email" do
    sign_in_as(@admin)
    get api_v1_players_path, params: { email: "john@example.com" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body.all? { |p| p["person"]["email"] == "john@example.com" }
  end

  test "index returns account status" do
    sign_in_as(@admin)
    get api_v1_players_path
    body = JSON.parse(response.body)
    john = body.find { |p| p["person_id"] == people(:one).id }
    assert_equal "Connected", john["account_status"]
  end

  test "show returns player detail" do
    profile = player_profiles(:john_player)
    sign_in_as(@admin)
    get api_v1_player_path(profile)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal profile.id, body["id"]
    assert_equal "John", body["person"]["first_name"]
    assert body.key?("account_status")
  end

  test "show returns 404 for missing player" do
    sign_in_as(@admin)
    get api_v1_player_path(99999)
    assert_response :not_found
  end

  test "create player requires coach or admin role" do
    sign_in_as(@public_user)
    post api_v1_players_path, params: { player: { person: { first_name: "Test" } } }
    assert_response :forbidden
  end

  test "cannot create player as regular player user" do
    sign_in_as(users(:two))
    post api_v1_players_path, params: player_create_params
    assert_response :forbidden
  end

  test "create player as coach" do
    sign_in_as(@trainer)

    post api_v1_players_path, params: coach_create_params

    assert_response :created
    body = JSON.parse(response.body)
    assert_kind_of Integer, body["id"]
    assert_equal "Pedro", body["person"]["first_name"]
    assert body["player_profile_id"].present?
    assert_equal "Active", body["status"]
    assert_equal "coach_created", body["person"]["creation_source"]
  end

  test "create returns validation errors" do
    sign_in_as(@admin)
    post api_v1_players_path, params: {
      player: { person: { first_name: "" }, player_profile: { preferred_position: "t libero" } }
    }
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_kind_of Array, body["errors"]
  end

  test "create player with profile attributes" do
    sign_in_as(@admin)
    count_before = player_profiles.count
    post api_v1_players_path, params: {
      player: {
        person: { first_name: "New", last_name: "Player" },
        player_profile: { preferred_position: "setter", level: "beginner" }
      }
    }
    assert_response :created
    assert_equal count_before + 1, player_profiles.reload.count
  end

  test "create player does not require last_name, email, or phone" do
    sign_in_as(@admin)
    post api_v1_players_path, params: {
      player: { person: { first_name: "Minimal" } }
    }
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "Minimal", body["person"]["first_name"]
  end

  private

  def player_create_params
    { player: {
      person: { first_name: "Test", last_name: "User" },
      player_profile: { preferred_position: "setter" }
    } }
  end

  def coach_create_params
    { player:
      { person: { first_name: "Pedro", last_name: "Santos", email: "pedro_coach_created_#{Time.now.to_i}@example.com" },
        player_profile: { preferred_position: "opposite", level: "intermediate" }
      }
    }
  end
end
