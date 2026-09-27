require "test_helper"

# Request tests for the Groups API (Phase A / Decision D23).
#
# Groups are reusable participant rosters (squads) for assessment sessions.
# They are a selection aid, not an authorization boundary.
# Read is open to training managers (coach/curator/admin).
# Create, update, destroy and membership manipulation require content creators (coach/admin).
# Deleting a group with associated assessment sessions is refused (archive instead).
class Api::V1::GroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)         # coach + admin
    @owner = users(:six)         # coach: created u19_squad fixture
    @other_coach = users(:three) # coach: created private_squad fixture
    @curator = users(:four)      # curator: training manager, not content creator
    @player_user = users(:one)   # player role only

    @u19 = groups(:u19_squad)
    @private_group = groups(:private_squad)
    @pedro = player_profiles(:pedro_player)
    @john = player_profiles(:john_player)
  end

  # --- Helpers ---

  def json
    JSON.parse(response.body)
  end

  def post_json(path, payload)
    post path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def patch_json(path, payload)
    patch path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  # --- Authentication & Authorization ---

  test "index requires authentication" do
    get api_v1_groups_path
    assert_response :unauthorized
  end

  test "index refuses player role" do
    sign_in_as(@player_user)
    get api_v1_groups_path
    assert_response :forbidden
  end

  test "curator can read index but cannot create groups" do
    sign_in_as(@curator)
    get api_v1_groups_path
    assert_response :success

    post_json api_v1_groups_path, { group: { name: "Curator Group" } }
    assert_response :forbidden
  end

  # --- Index & Search ---

  test "index lists active groups visible to the caller" do
    sign_in_as(@owner)
    get api_v1_groups_path
    assert_response :success

    body = json
    assert_kind_of Array, body["data"]
    assert_kind_of Array, body["groups"]
    names = body["data"].map { |g| g["name"] }
    assert_includes names, "U19 squad"
    assert_not_includes names, "Private squad" # private to other_coach
  end

  test "index includes private groups for admins and curators" do
    sign_in_as(@admin)
    get api_v1_groups_path
    assert_response :success

    names = json["data"].map { |g| g["name"] }
    assert_includes names, "U19 squad"
    assert_includes names, "Private squad"
  end

  test "index filters by search query" do
    sign_in_as(@admin)
    get api_v1_groups_path, params: { q: "U19" }
    assert_response :success

    names = json["data"].map { |g| g["name"] }
    assert_includes names, "U19 squad"
    assert_not_includes names, "Private squad"
  end

  test "index filters by status" do
    @u19.update!(status: "archived")
    sign_in_as(@admin)

    get api_v1_groups_path
    names = json["data"].map { |g| g["name"] }
    assert_not_includes names, "U19 squad"

    get api_v1_groups_path, params: { status: "archived" }
    archived_names = json["data"].map { |g| g["name"] }
    assert_includes archived_names, "U19 squad"
  end

  test "index supports mine filter" do
    sign_in_as(@owner)
    get api_v1_groups_path, params: { mine: 1 }
    assert_response :success

    names = json["data"].map { |g| g["name"] }
    assert_includes names, "U19 squad"
    assert_equal 1, names.length
  end

  # --- Show ---

  test "show returns detailed group with members" do
    sign_in_as(@owner)
    get api_v1_group_path(@u19)
    assert_response :success

    group_data = json["group"]
    assert_equal @u19.id, group_data["id"]
    assert_equal "U19 squad", group_data["name"]
    assert_equal 1, group_data["player_count"]
    assert_equal 1, group_data["members"].length
    assert_equal @pedro.id, group_data["members"].first["player_profile_id"]
    assert_equal "Pedro Santos", group_data["members"].first["player_name"]
  end

  test "show supports slug lookup" do
    sign_in_as(@owner)
    get api_v1_group_path(@u19.slug)
    assert_response :success
    assert_equal @u19.id, json["group"]["id"]
  end

  test "show returns 404 for another coach's private group" do
    sign_in_as(@owner)
    get api_v1_group_path(@private_group)
    assert_response :not_found
  end

  test "show allows owner or admin to view private group" do
    sign_in_as(@other_coach)
    get api_v1_group_path(@private_group)
    assert_response :success
  end

  # --- Create ---

  test "create creates a new group with optional initial players" do
    sign_in_as(@owner)

    payload = {
      group: {
        name: "Morning Elite",
        description: "Competitive training group",
        visibility: "shared"
      },
      player_profile_ids: [ @john.id, @pedro.id ]
    }

    assert_difference "Group.count", 1 do
      assert_difference "GroupMembership.count", 2 do
        post_json api_v1_groups_path, payload
      end
    end

    assert_response :created
    group_data = json["group"]
    assert_equal "Morning Elite", group_data["name"]
    assert_equal "morning-elite", group_data["slug"]
    assert_equal 2, group_data["player_count"]
    assert_equal @owner.id, group_data["created_by"]["id"]
  end

  test "create validates unique name" do
    sign_in_as(@owner)

    post_json api_v1_groups_path, { group: { name: "u19 squad" } }
    assert_response :unprocessable_entity
    assert json["errors"].any? { |e| e.downcase.include?("name") }
  end

  # --- Update ---

  test "update modifies group details and syncs members" do
    sign_in_as(@owner)

    patch_json api_v1_group_path(@u19), {
      group: { name: "U19 Premier Squad", description: "Updated description" },
      player_profile_ids: [ @john.id ]
    }

    assert_response :success
    assert_equal "U19 Premier Squad", json["group"]["name"]
    assert_equal "Updated description", json["group"]["description"]
    assert_equal 1, json["group"]["player_count"]
    assert_equal @john.id, json["group"]["members"].first["player_profile_id"]
  end

  test "update is forbidden for another coach who does not own the group" do
    sign_in_as(@other_coach)

    patch_json api_v1_group_path(@u19), { group: { name: "Hacked" } }
    assert_response :forbidden
  end

  test "admin can update any group" do
    sign_in_as(@admin)

    patch_json api_v1_group_path(@u19), { group: { description: "Admin edit" } }
    assert_response :success
    assert_equal "Admin edit", json["group"]["description"]
  end

  # --- Destroy ---

  test "destroy deletes group if not used in assessment sessions" do
    sign_in_as(@owner)

    assert_difference "Group.count", -1 do
      delete api_v1_group_path(@u19)
    end

    assert_response :success
    assert_equal "Group deleted successfully", json["message"]
  end

  test "destroy refuses to delete group when referenced by assessment sessions" do
    sign_in_as(@owner)
    session = assessment_sessions(:draft_squad)
    session.update!(group: @u19)

    assert_no_difference "Group.count" do
      delete api_v1_group_path(@u19)
    end

    assert_response :unprocessable_entity
    assert json["errors"].any? { |e| e.include?("assessment sessions") }
  end

  # --- Member Management ---

  test "add_members adds player to group without duplicates" do
    sign_in_as(@owner)

    assert_difference "GroupMembership.count", 1 do
      post_json members_api_v1_group_path(@u19), { player_profile_ids: [ @john.id, @pedro.id ] }
    end

    assert_response :success
    assert_equal 2, json["group"]["player_count"]
    assert_equal 1, json["added"]
  end

  test "remove_member removes player from group" do
    sign_in_as(@owner)

    assert_difference "GroupMembership.count", -1 do
      delete "#{api_v1_groups_path}/#{@u19.id}/members/#{@pedro.id}"
    end

    assert_response :success
    assert_equal 0, json["group"]["player_count"]
    assert_equal @pedro.id, json["removed"]
  end

  test "remove_member returns 404 if player is not in group" do
    sign_in_as(@owner)

    delete "#{api_v1_groups_path}/#{@u19.id}/members/#{@john.id}"
    assert_response :not_found
  end
end
