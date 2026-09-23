require "test_helper"

class Api::V1::PlayersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @public_user = users(:one)   # player role only
    @trainer = users(:three)     # coach role only
    @admin = users(:two)         # coach + admin
    @curator = users(:four)      # curator: manages trainings, not content
  end

  test "index returns all active players" do
    sign_in_as(@admin)
    get api_v1_players_path
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body["data"]
    player_ids = body["data"].map { |p| p["id"] }
    assert_includes player_ids, player_profiles(:john_player).id
    assert_includes player_ids, player_profiles(:pedro_player).id
  end

  test "index paginates 20 per page by default" do
    sign_in_as(@admin)
    25.times do |index|
      Person.create!(first_name: "Paged#{format('%02d', index)}", last_name: "Zzz",
                     creation_source: "system").create_player_profile!
    end

    get api_v1_players_path
    body = JSON.parse(response.body)
    assert_equal 20, body["data"].length
    assert_equal 20, body["meta"]["per_page"]
    assert_equal 1, body["meta"]["page"]
    assert_equal 27, body["meta"]["total"]
    assert_equal 2, body["meta"]["total_pages"]

    get api_v1_players_path, params: { page: 2 }
    second = JSON.parse(response.body)
    assert_equal 7, second["data"].length
    assert_equal [], body["data"].map { |p| p["id"] } & second["data"].map { |p| p["id"] },
                 "pages must not overlap"
  end

  test "index clamps per_page to a sane band" do
    sign_in_as(@admin)

    get api_v1_players_path, params: { per_page: 5000 }
    assert_equal 100, JSON.parse(response.body)["meta"]["per_page"]

    get api_v1_players_path, params: { per_page: 0, page: 0 }
    meta = JSON.parse(response.body)["meta"]
    assert_equal 20, meta["per_page"]
    assert_equal 1, meta["page"]
  end

  test "index keeps the search when paging" do
    sign_in_as(@admin)
    get api_v1_players_path, params: { q: "John", page: 1 }

    body = JSON.parse(response.body)
    assert_equal 1, body["meta"]["total"]
    assert body["data"].all? { |player| player["full_name"].downcase.include?("john") }
  end

  test "index orders players by last name, then first name" do
    sign_in_as(@admin)
    get api_v1_players_path
    body = JSON.parse(response.body)
    keys = body["data"].map { |p| [ p["person"]["last_name"].to_s, p["person"]["first_name"].to_s, p["id"] ] }
    assert_equal keys.sort, keys, "ordered by last_name, first_name, id"
  end

  test "index filters by name search" do
    sign_in_as(@admin)
    get api_v1_players_path, params: { q: "John" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body["data"].all? { |p| p["full_name"].downcase.include?("john") }
  end

  test "index filters by email" do
    sign_in_as(@admin)
    get api_v1_players_path, params: { email: "one@example.com" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ people(:one).id ], body["data"].map { |p| p["person_id"] }
  end

  test "index returns account status" do
    sign_in_as(@admin)
    get api_v1_players_path
    body = JSON.parse(response.body)
    john = body["data"].find { |p| p["person_id"] == people(:one).id }
    assert_equal "connected", john["account_status"]
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

  test "cannot create player as curator" do
    sign_in_as(@curator)
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
    assert_equal "active", body["status"]
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
    count_before = PlayerProfile.count
    post api_v1_players_path, params: {
      player: {
        person: { first_name: "New", last_name: "Player" },
        player_profile: { preferred_position: "setter", level: "beginner" }
      }
    }
    assert_response :created
    assert_equal count_before + 1, PlayerProfile.count
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

  test "create player links an existing person instead of creating one" do
    sign_in_as(@admin)
    person = Person.create!(first_name: "Linkable", last_name: "Person", creation_source: "system")
    people_before = Person.count

    post api_v1_players_path, params: {
      player: { person_id: person.id, player_profile: { preferred_position: "setter" } }
    }

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal person.id, body["person_id"]
    assert_equal person.id, body["person"]["id"]
    assert_equal people_before, Person.count, "no new person should be recorded"
    assert_equal "system", person.reload.creation_source, "linking must not rewrite provenance"
  end

  test "create player reports possible duplicates as suggestions only" do
    sign_in_as(@admin)
    existing = people(:accountless_player)

    post api_v1_players_path, params: {
      player: { person: { first_name: "Pedro", last_name: "Santos" }, player_profile: {} }
    }

    assert_response :created
    body = JSON.parse(response.body)
    duplicate_ids = body["possible_duplicates"].map { |duplicate| duplicate["id"] }

    assert_includes duplicate_ids, existing.id
    assert_not_includes duplicate_ids, body["person"]["id"], "a person is never its own duplicate"
    assert_nil existing.reload.merged_into_id, "duplicates are never merged automatically"
    assert_equal "profile_only", body["possible_duplicates"].first["account_status"]
  end

  test "create player reports no duplicates for a unique person" do
    sign_in_as(@admin)
    post api_v1_players_path, params: {
      player: { person: { first_name: "Unique", last_name: "Onlyone", email: "unique_onlyone@example.com" },
                player_profile: {} }
    }

    assert_response :created
    assert_equal [], JSON.parse(response.body)["possible_duplicates"]
  end

  test "create player rejects a person who already has a player profile" do
    sign_in_as(@admin)
    existing = player_profiles(:john_player)

    post api_v1_players_path, params: {
      player: { person_id: existing.person_id, player_profile: {} }
    }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Person has already been taken"
  end

  test "create player rejects an unknown person_id" do
    sign_in_as(@admin)

    post api_v1_players_path, params: {
      player: { person_id: 0, player_profile: {} }
    }

    assert_response :unprocessable_entity
    assert_kind_of Array, JSON.parse(response.body)["errors"]
  end

  test "index hides archived players by default and lists them on request" do
    sign_in_as(@admin)
    archived = player_profiles(:pedro_player)
    archived.update!(status: "archived")

    get api_v1_players_path
    default_ids = JSON.parse(response.body)["data"].map { |p| p["id"] }
    assert_not_includes default_ids, archived.id
    assert_includes default_ids, player_profiles(:john_player).id

    get api_v1_players_path, params: { status: "archived" }
    archived_ids = JSON.parse(response.body)["data"].map { |p| p["id"] }
    assert_equal [ archived.id ], archived_ids
  end

  test "index rejects an unknown status filter" do
    sign_in_as(@admin)

    get api_v1_players_path, params: { status: "retired" }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "status is not included in the list"
  end

  test "archiving keeps the training history" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)
    session = TrainingSession.create!(title: "Archive check", created_by: users(:two),
                                      starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)
    participant = session.training_session_participants.create!(player_profile: player)
    history_before = player.training_session_count

    patch api_v1_player_path(player), params: { player: { player_profile: { status: "archived" } } }

    assert_response :success
    assert_equal "archived", player.reload.status
    # Archiving is a flag, not a deletion: every roster row and its attendance
    # must survive it.
    assert_equal history_before, player.training_session_count
    assert_includes player.training_session_participants, participant.reload
    assert_equal 1, TrainingSessionParticipant.where(id: participant.id).count
  end

  test "an archived player can be restored" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)
    player.update!(status: "archived")

    patch api_v1_player_path(player), params: { player: { player_profile: { status: "active" } } }

    assert_response :success
    assert_equal "active", player.reload.status

    get api_v1_players_path
    assert_includes JSON.parse(response.body)["data"].map { |p| p["id"] }, player.id
  end

  test "archived players are not offered to the participant picker" do
    sign_in_as(@admin)
    player_profiles(:pedro_player).update!(status: "archived")

    get api_v1_players_path, params: { per_page: 100 }

    assert_not_includes JSON.parse(response.body)["data"].map { |p| p["id"] }, player_profiles(:pedro_player).id
  end

  test "there is no hard delete for a player" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)

    # The route is deliberately absent: archiving is the only removal path, so
    # attendance history can never be destroyed by an API call.
    delete "/api/v1/players/#{player.id}"

    assert_response :not_found
    assert PlayerProfile.exists?(player.id)
  end

  test "update player as coach changes profile and person attributes" do
    sign_in_as(@trainer)
    player = player_profiles(:pedro_player)

    patch api_v1_player_path(player), params: {
      player: {
        player_profile: { preferred_position: "blocker", level: "advanced" },
        person: { first_name: "Pedro", last_name: "Santos", email: "pedro@example.com" }
      }
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "blocker", body["preferred_position"]
    assert_equal "advanced", body["level"]
    assert_equal "pedro@example.com", body["person"]["email"]
    assert_equal "blocker", player.reload.preferred_position
  end

  test "update player requires a content creator" do
    player = player_profiles(:pedro_player)

    sign_in_as(@public_user)
    patch api_v1_player_path(player), params: { player: { player_profile: { level: "advanced" } } }
    assert_response :forbidden

    sign_out
    sign_in_as(@curator)
    patch api_v1_player_path(player), params: { player: { player_profile: { level: "advanced" } } }
    assert_response :forbidden

    assert_equal "beginner", player.reload.level
  end

  test "update player requires authentication" do
    patch api_v1_player_path(player_profiles(:pedro_player)), params: { player: { player_profile: { level: "advanced" } } }
    assert_response :unauthorized
  end

  test "update returns 404 for an unknown player" do
    sign_in_as(@admin)
    patch api_v1_player_path(0), params: { player: { player_profile: { level: "advanced" } } }
    assert_response :not_found
  end

  test "update returns validation errors" do
    sign_in_as(@admin)
    patch api_v1_player_path(player_profiles(:pedro_player)), params: {
      player: { person: { first_name: "" } }
    }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "Person first name can't be blank"
  end

  test "update does not replace the person behind the profile" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)
    person = player.person
    people_before = Person.count

    patch api_v1_player_path(player), params: { player: { person: { first_name: "Peter" } } }

    assert_response :success
    assert_equal person.id, player.reload.person_id, "the profile must keep its person"
    assert_equal people_before, Person.count, "no second identity may be created"
    assert_equal "Peter", person.reload.first_name
    assert_equal "Santos", person.last_name, "unsent attributes are preserved"
  end

  test "update cannot move a profile to another person" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)

    patch api_v1_player_path(player), params: {
      player: { person_id: people(:two).id, player_profile: { level: "advanced" } }
    }

    assert_response :unprocessable_entity
    assert_equal player.person_id, player.reload.person_id
    assert_equal "beginner", player.level
  end

  test "update ignores a person_id that names the same person" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)

    patch api_v1_player_path(player), params: {
      player: { person_id: player.person_id, player_profile: { level: "advanced" } }
    }

    assert_response :success
    assert_equal "advanced", player.reload.level
  end

  test "update records the previous name as an alias" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)

    patch api_v1_player_path(player), params: {
      player: { person: { first_name: "Peter" } }
    }

    assert_response :success
    assert_equal [ "Pedro Santos" ], player.person.reload.person_aliases.pluck(:full_name)
  end

  test "update returns possible duplicates after a rename" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)

    patch api_v1_player_path(player), params: {
      player: { person: { first_name: "John", last_name: "Smith" } }
    }

    assert_response :success
    duplicate_ids = JSON.parse(response.body)["possible_duplicates"].map { |duplicate| duplicate["id"] }
    assert_includes duplicate_ids, people(:one).id
    assert_not_includes duplicate_ids, player.person_id
  end

  test "update clears a contact field when a blank value is sent" do
    sign_in_as(@admin)
    person = Person.create!(first_name: "Clearable", last_name: "Player", email: "clear@example.com",
                            creation_source: "system")
    player = person.create_player_profile!

    patch api_v1_player_path(player), params: { player: { person: { email: "" } } }

    assert_response :success
    assert_nil person.reload.email
  end

  test "update does not rewrite provenance" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)
    person = player.person

    patch api_v1_player_path(player), params: { player: { player_profile: { level: "advanced" } } }

    assert_response :success
    assert_equal "coach_created", person.reload.creation_source
    assert_equal users(:two).id, person.created_by_id
  end

  test "update can archive a player through the status attribute" do
    sign_in_as(@admin)
    player = player_profiles(:pedro_player)

    patch api_v1_player_path(player), params: { player: { player_profile: { status: "archived" } } }

    assert_response :success
    assert_equal "archived", player.reload.status
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
      { person: { first_name: "Pedro", last_name: "Santos", email: "pedro_created_by_coach@example.com" },
        player_profile: { preferred_position: "opposite", level: "intermediate" }
      }
    }
  end
end
