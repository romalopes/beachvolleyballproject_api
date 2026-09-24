require "test_helper"

# Request tests for the Training Sessions API.
#
# Visibility (who may see a training) and management (who may mutate one) are
# deliberately separate: guests/players can read the shared schedule, while
# coaches, curators and admins manage it regardless of who created it.
class Api::V1::TrainingSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)     # coach + admin
    @coach = users(:three)   # coach only
    @curator = users(:four)  # curator only
    @player = users(:one)    # player only

    @skill = skills(:one)
    @other_skill = skills(:two)
    @drill = drills(:one)
    @other_drill = drills(:two)

    # The drills fixture does not declare skill links; the training payload
    # exposes whatever the drill references.
    DrillSkill.find_or_create_by!(drill: @drill, skill: @skill)

    @session = training_sessions(:one)  # scheduled, created_by the coach
    @draft = training_sessions(:two)    # draft, created_by the coach
  end

  # --- helpers -------------------------------------------------------------

  def json
    JSON.parse(response.body)
  end

  # The JSON API is consumed by the React SPA, which sends JSON bodies. Using
  # the JSON content type also avoids Rails' form-encoding quirks with nested
  # arrays of hashes whose keys differ per row.
  def post_json(path, payload)
    post path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def patch_json(path, payload)
    patch path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def valid_payload(overrides = {})
    {
      title: "New Training",
      description: "A structured session.",
      location: "Coogee Beach",
      status: "scheduled",
      starts_at: "2026-10-01T09:00:00Z",
      ends_at: "2026-10-01T11:00:00Z"
    }.merge(overrides)
  end

  # A minimal but valid v1 visual definition (mirrors DrillDefinitionTest).
  def minimal_definition
    {
      "version" => 1,
      "view" => { "orientation" => "top_down" },
      "side" => { "grid" => { "columns" => 5, "rows" => 4 } },
      "participants" => [ { "id" => "P1", "type" => "player", "role" => "attacker" } ],
      "balls" => [ { "id" => "B1", "type" => "volleyball" } ],
      "objects" => [],
      "steps" => [
        {
          "id" => "S1",
          "description" => "Serve.",
          "participants" => [ { "id" => "P1", "active" => true, "location" => { "side" => "side_1", "x" => 3, "y" => 2 } } ],
          "balls" => [ { "id" => "B1", "active" => true, "location" => { "side" => "side_1", "x" => 3, "y" => 2 } } ],
          "objects" => [],
          "actions" => [ { "participant_id" => "P1", "action" => { "type" => "serve", "description" => "Serve." } } ],
          "participant_movements" => [],
          "ball_movements" => [ { "ball_id" => "B1", "from" => { "side" => "side_1", "x" => 3, "y" => 2 }, "to" => { "side" => "side_2", "x" => 3, "y" => 2 } } ],
          "object_movements" => []
        },
        {
          "id" => "S2",
          "description" => "Receive.",
          "participants" => [ { "id" => "P1", "active" => true, "location" => { "side" => "side_2", "x" => 3, "y" => 2 } } ],
          "balls" => [ { "id" => "B1", "active" => true, "location" => { "side" => "side_2", "x" => 3, "y" => 2 } } ],
          "objects" => [],
          "actions" => [],
          "participant_movements" => [],
          "ball_movements" => [],
          "object_movements" => []
        }
      ]
    }
  end

  # --- index ---------------------------------------------------------------

  test "index is public and returns the shared schedule without drafts" do
    get "/api/v1/training_sessions"

    assert_response :success
    titles = json.map { |session| session["title"] }
    assert_includes titles, @session.title
    assert_includes titles, training_sessions(:three).title
    assert_not_includes titles, @draft.title
  end

  test "index returns a calendar-light payload" do
    get "/api/v1/training_sessions"

    entry = json.first
    assert_equal %w[created_by created_by_id duration_minutes ends_at id location starts_at status status_label title visibility],
                 entry.keys.sort
    assert_not entry.key?("drill")
    assert_not entry.key?("training_focuses")
    assert_not entry.key?("training_session_drills")
  end

  test "index is ordered by start time" do
    get "/api/v1/training_sessions"

    starts = json.map { |session| session["starts_at"] }
    assert_equal starts.sort, starts
  end

  test "index hides drafts from players" do
    sign_in_as(@player)
    get "/api/v1/training_sessions"

    assert_response :success
    assert_not_includes json.map { |s| s["title"] }, @draft.title
  end

  test "index shows drafts to coaches, curators and admins" do
    [ @coach, @curator, @admin ].each do |manager|
      sign_in_as(manager)
      get "/api/v1/training_sessions"
      assert_includes json.map { |s| s["title"] }, @draft.title, "expected #{manager.name} to see drafts"
    end
  end

  test "index shows sessions created by other users (shared calendar)" do
    sign_in_as(@coach)
    get "/api/v1/training_sessions"

    assert_includes json.map { |s| s["title"] }, training_sessions(:three).title
  end

  test "index filters by date range" do
    get "/api/v1/training_sessions?starts_at_from=2026-09-21&starts_at_to=2026-09-22"

    titles = json.map { |s| s["title"] }
    assert_includes titles, @session.title
    assert_not_includes titles, training_sessions(:three).title
  end

  test "index rejects an invalid date filter" do
    get "/api/v1/training_sessions?starts_at_from=not-a-date"

    assert_response :unprocessable_entity
    assert_includes json["errors"], "starts_at_from is not a valid date"
  end

  test "index rejects an invalid status filter" do
    get "/api/v1/training_sessions?status=active"

    assert_response :unprocessable_entity
    assert_includes json["errors"], "status is not included in the list"
  end

  test "index filters by status" do
    sign_in_as(@coach)
    get "/api/v1/training_sessions?status=draft"

    assert_response :success
    # Coaches (managers) see all draft sessions, including private ones.
    titles = json.map { |s| s["title"] }.sort
    assert_includes titles, @draft.title
    assert_includes titles, "Private Drill Design"
  end

  # --- show ----------------------------------------------------------------

  test "show returns the complete training payload" do
    get "/api/v1/training_sessions/#{@session.id}"

    assert_response :success
    body = json
    assert_equal @session.title, body["title"]
    assert_equal "scheduled", body["status"]
    assert_equal "Scheduled", body["status_label"]
    assert_equal 120, body["duration_minutes"]
    assert_equal @coach.id, body["created_by_id"]

    focuses = body["training_focuses"]
    assert_equal [ 0, 1 ], focuses.map { |f| f["position"] }
    skill_focus = focuses.first
    assert_equal @skill.id, skill_focus["skill"]["id"]
    assert_equal categories(:one).name, skill_focus["skill"]["category"]["name"]
    assert_equal "Focus on platform angle against float serves.", skill_focus["description"]
    custom_focus = focuses.last
    assert_nil custom_focus["skill_id"]
    assert_equal "Transition communication", custom_focus["custom_focus"]
    assert_equal "Players should call early after the block.", custom_focus["description"]
    assert_equal "Transition communication", custom_focus["label"]
  end

  test "show exposes session-specific drill data without touching the drill" do
    get "/api/v1/training_sessions/#{@session.id}"

    entries = json["training_session_drills"]
    assert_equal [ 0, 1 ], entries.map { |entry| entry["position"] }
    first = entries.first
    assert_equal @drill.id, first["drill_id"]
    assert_equal 15, first["duration_minutes"]
    assert_equal "Use stronger serves for the second round.", first["notes"]

    drill = first["drill"]
    assert_equal @drill.title, drill["title"]
    assert_not drill.key?("created_by_id")
    assert drill.key?("definition")
    assert_equal @skill.id, drill["skills"].first["id"]
  end

  test "show exposes the drill visual definition and steps" do
    drill = Drill.create!(title: "Visual Drill", slug: "visual-drill-test",
                          definition: minimal_definition)
    @session.training_session_drills.create!(drill: drill, position: 9, duration_minutes: 25)

    get "/api/v1/training_sessions/#{@session.id}"

    entry = json["training_session_drills"].find { |e| e["drill_id"] == drill.id }
    assert_equal 25, entry["duration_minutes"]
    steps = entry["drill"]["definition"]["steps"]
    assert_equal 2, steps.size
    assert_equal "Serve.", steps.first["description"]
  end

  test "show returns 404 for a draft when the viewer is not a manager" do
    [ nil, @player ].each do |viewer|
      sign_in_as(viewer) if viewer
      get "/api/v1/training_sessions/#{@draft.id}"
      assert_response :not_found, "expected draft to be hidden from #{viewer&.name || 'guest'}"
      assert_equal "Training Session not found", json["error"]
    end
  end

  test "show returns a draft to managers" do
    [ @coach, @curator, @admin ].each do |manager|
      sign_in_as(manager)
      get "/api/v1/training_sessions/#{@draft.id}"
      assert_response :success
      assert_equal @draft.title, json["title"]
    end
  end

  test "show returns 404 for an unknown id" do
    get "/api/v1/training_sessions/999999"

    assert_response :not_found
    assert_equal "Training Session not found", json["error"]
  end

  # --- create --------------------------------------------------------------

  test "coach creates a training with skill and custom focuses and ordered drills" do
    sign_in_as(@coach)

    assert_difference("TrainingSession.count") do
      assert_difference("TrainingFocus.count", 2) do
        assert_difference("TrainingSessionDrill.count", 2) do
          post_json "/api/v1/training_sessions", training_session: valid_payload(
            training_focuses_attributes: [
              { skill_id: @skill.id, description: "Platform angle against float serves." },
              { custom_focus: "Transition communication", description: "Call early after the block." }
            ],
            training_session_drills_attributes: [
              { drill_id: @other_drill.id, duration_minutes: 30, notes: "Second drill first." },
              { drill_id: @drill.id, duration_minutes: 15 }
            ]
          )
        end
      end
    end

    assert_response :created
    body = json
    assert_equal @coach.id, body["created_by_id"]
    assert_equal [ 0, 1 ], body["training_focuses"].map { |f| f["position"] }
    assert_equal [ "MyString", "Transition communication" ], body["training_focuses"].map { |f| f["label"] }
    assert_equal [ 0, 1 ], body["training_session_drills"].map { |d| d["position"] }
    assert_equal [ @other_drill.id, @drill.id ], body["training_session_drills"].map { |d| d["drill_id"] }
    assert_equal [ 30, 15 ], body["training_session_drills"].map { |d| d["duration_minutes"] }
    assert_equal "Second drill first.", body["training_session_drills"].first["notes"]
  end

  test "curator and admin can create trainings" do
    [ @curator, @admin ].each do |manager|
      sign_in_as(manager)
      assert_difference("TrainingSession.count") do
        post_json "/api/v1/training_sessions", training_session: valid_payload(title: "By #{manager.name}")
      end
      assert_response :created
      assert_equal manager.id, TrainingSession.find(json["id"]).created_by_id
    end
  end

  test "created_by comes from the authenticated user, never the payload" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions",
         training_session: valid_payload(created_by_id: @player.id)

    assert_response :created
    assert_equal @coach.id, json["created_by_id"]
    assert_equal @coach.id, TrainingSession.find(json["id"]).created_by_id
  end

  test "the training workflow never creates skills or drills" do
    sign_in_as(@coach)

    assert_no_difference([ "Skill.count", "Drill.count" ]) do
      post_json "/api/v1/training_sessions", training_session: valid_payload(
        training_focuses_attributes: [
          { skill_id: @skill.id },
          { custom_focus: "Transition communication" }
        ],
        training_session_drills_attributes: [ { drill_id: @drill.id } ]
      )
    end

    assert_response :created
  end

  test "player cannot create a training" do
    sign_in_as(@player)
    assert_no_difference("TrainingSession.count") do
      post_json "/api/v1/training_sessions", training_session: valid_payload
    end

    assert_response :forbidden
  end

  test "guest cannot create a training" do
    assert_no_difference("TrainingSession.count") do
      post_json "/api/v1/training_sessions", training_session: valid_payload
    end

    assert_response :unauthorized
  end

  test "create requires a title" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions", training_session: valid_payload(title: "")

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Title can't be blank"
  end

  test "create requires start and end times" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions",
         training_session: { title: "No dates" }

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Starts at can't be blank"
    assert_includes json["errors"], "Ends at can't be blank"
  end

  test "create rejects an end time before the start time" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions", training_session: valid_payload(
      starts_at: "2026-10-01T11:00:00Z", ends_at: "2026-10-01T09:00:00Z"
    )

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Ends at must be after the start time"
  end

  test "create rejects an invalid status" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions", training_session: valid_payload(status: "active")

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Status is not included in the list"
  end

  test "create rejects an empty focus" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions", training_session: valid_payload(
      training_focuses_attributes: [ { description: "No skill and no custom text" } ]
    )

    assert_response :unprocessable_entity
    assert_includes json["errors"],
                    "Training focuses A training focus must reference a skill or provide custom focus text"
  end

  test "create rejects a focus with both a skill and custom text" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions", training_session: valid_payload(
      training_focuses_attributes: [ { skill_id: @skill.id, custom_focus: "Both" } ]
    )

    assert_response :unprocessable_entity
    assert_includes json["errors"],
                    "Training focuses A training focus cannot reference a skill and custom text at the same time"
  end

  test "create rejects the same skill twice in one training" do
    sign_in_as(@coach)
    assert_no_difference("TrainingFocus.count") do
      post_json "/api/v1/training_sessions", training_session: valid_payload(
        training_focuses_attributes: [ { skill_id: @skill.id }, { skill_id: @skill.id } ]
      )
    end

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Skills must be unique within a training session"
  end

  test "create allows repeated custom focus text" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions", training_session: valid_payload(
      training_focuses_attributes: [
        { custom_focus: "Transition communication" },
        { custom_focus: "Transition communication" }
      ]
    )

    assert_response :created
    assert_equal 2, json["training_focuses"].size
  end

  test "create rejects the same drill twice in one training" do
    sign_in_as(@coach)
    assert_no_difference("TrainingSessionDrill.count") do
      post_json "/api/v1/training_sessions", training_session: valid_payload(
        training_session_drills_attributes: [ { drill_id: @drill.id }, { drill_id: @drill.id } ]
      )
    end

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Drills must be unique within a training session"
  end

  test "create rejects a non-positive duration" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions", training_session: valid_payload(
      training_session_drills_attributes: [ { drill_id: @drill.id, duration_minutes: 0 } ]
    )

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Training session drills duration minutes must be greater than 0"
  end

  test "create rejects a nonexistent skill" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions", training_session: valid_payload(
      training_focuses_attributes: [ { skill_id: 999_999 } ]
    )

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Training focuses skill must exist"
  end

  test "create rejects a nonexistent drill" do
    sign_in_as(@coach)
    post_json "/api/v1/training_sessions", training_session: valid_payload(
      training_session_drills_attributes: [ { drill_id: 999_999 } ]
    )

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Training session drills drill must exist"
  end

  # --- update --------------------------------------------------------------

  test "a coach can update a training created by another user" do
    sign_in_as(@coach)
    patch_json "/api/v1/training_sessions/#{training_sessions(:three).id}",
          training_session: { title: "Renamed by another coach" }

    assert_response :success
    assert_equal "Renamed by another coach", training_sessions(:three).reload.title
  end

  test "a curator can update a training created by a coach" do
    sign_in_as(@curator)
    patch_json "/api/v1/training_sessions/#{@session.id}",
          training_session: { title: "Curated", status: "completed" }

    assert_response :success
    assert_equal "Curated", @session.reload.title
    assert_equal "completed", @session.status
  end

  test "update changes dates and location" do
    sign_in_as(@coach)
    patch_json "/api/v1/training_sessions/#{@session.id}", training_session: {
      starts_at: "2026-09-21T14:00:00Z", ends_at: "2026-09-21T16:30:00Z", location: "Maroubra"
    }

    assert_response :success
    assert_equal 150, json["duration_minutes"]
    assert_equal "Maroubra", @session.reload.location
  end

  test "update rejects an end time before the start time" do
    sign_in_as(@coach)
    patch_json "/api/v1/training_sessions/#{@session.id}", training_session: {
      starts_at: "2026-09-21T14:00:00Z", ends_at: "2026-09-21T13:00:00Z"
    }

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Ends at must be after the start time"
  end

  test "update reorders focuses and keeps their positions" do
    sign_in_as(@curator)
    first, second = @session.training_focuses.order(:position).to_a

    patch_json "/api/v1/training_sessions/#{@session.id}", training_session: {
      training_focuses_attributes: [
        { id: second.id, position: 0 },
        { id: first.id, position: 1 }
      ]
    }

    assert_response :success
    assert_equal [ second.id, first.id ], json["training_focuses"].map { |f| f["id"] }
    assert_equal [ 0, 1 ], json["training_focuses"].map { |f| f["position"] }
  end

  test "update replaces a skill focus with a custom focus" do
    sign_in_as(@coach)
    skill_focus = @session.training_focuses.find_by(skill_id: @skill.id)

    patch_json "/api/v1/training_sessions/#{@session.id}", training_session: {
      training_focuses_attributes: [ { id: skill_focus.id, custom_focus: "Now a custom focus", skill_id: nil } ]
    }

    assert_response :success
    skill_focus.reload
    assert_nil skill_focus.skill_id
    assert_equal "Now a custom focus", skill_focus.custom_focus
  end

  test "update removes drills without deleting the drill record" do
    sign_in_as(@coach)
    removed = @session.training_session_drills.order(:position).first
    kept = @session.training_session_drills.order(:position).last

    assert_difference("TrainingSessionDrill.count", -1) do
      patch_json "/api/v1/training_sessions/#{@session.id}", training_session: {
        training_session_drills_attributes: [
          { id: removed.id, _destroy: "1" },
          { id: kept.id, position: 0, duration_minutes: 45, notes: "Now first and longer" }
        ]
      }
    end

    assert_response :success
    assert_equal [ kept.id ], json["training_session_drills"].map { |d| d["id"] }
    assert_equal 45, json["training_session_drills"].first["duration_minutes"]
    assert_equal "Now first and longer", json["training_session_drills"].first["notes"]
    assert Drill.exists?(removed.drill_id), "the drill itself must survive"
  end

  test "update changes the status to cancelled" do
    sign_in_as(@coach)
    patch_json "/api/v1/training_sessions/#{@session.id}",
          training_session: { status: "cancelled" }

    assert_response :success
    assert_equal "cancelled", @session.reload.status
    assert_equal "Cancelled", json["status_label"]
  end

  test "player cannot update a training" do
    sign_in_as(@player)
    patch_json "/api/v1/training_sessions/#{@session.id}",
          training_session: { title: "Hacked" }

    assert_response :forbidden
    assert_equal "Serve Reception Training", @session.reload.title
  end

  test "guest cannot update a training" do
    patch_json "/api/v1/training_sessions/#{@session.id}",
          training_session: { title: "Hacked" }

    assert_response :unauthorized
    assert_equal "Serve Reception Training", @session.reload.title
  end

  test "update returns 404 for an unknown id" do
    sign_in_as(@coach)
    patch_json "/api/v1/training_sessions/999999", training_session: { title: "Ghost" }

    assert_response :not_found
  end

  # --- destroy -------------------------------------------------------------

  test "a coach can delete a training created by another user" do
    sign_in_as(@coach)
    target = training_sessions(:three)

    assert_difference("TrainingSession.count", -1) do
      delete "/api/v1/training_sessions/#{target.id}"
    end

    assert_response :no_content
  end

  test "a curator can delete a training" do
    sign_in_as(@curator)

    assert_difference("TrainingSession.count", -1) do
      delete "/api/v1/training_sessions/#{@session.id}"
    end

    assert_response :no_content
  end

  test "deleting a training removes its focuses and drill links, not the drills" do
    sign_in_as(@admin)
    drill_count = Drill.count

    assert_difference([ "TrainingFocus.count", "TrainingSessionDrill.count" ], -2) do
      delete "/api/v1/training_sessions/#{@session.id}"
    end

    assert_response :no_content
    assert_equal drill_count, Drill.count
  end

  test "player cannot delete a training" do
    sign_in_as(@player)

    assert_no_difference("TrainingSession.count") do
      delete "/api/v1/training_sessions/#{@session.id}"
    end

    assert_response :forbidden
  end

  test "guest cannot delete a training" do
    assert_no_difference("TrainingSession.count") do
      delete "/api/v1/training_sessions/#{@session.id}"
    end

    assert_response :unauthorized
  end

  test "delete returns 404 for an unknown id" do
    sign_in_as(@admin)
    delete "/api/v1/training_sessions/999999"

    assert_response :not_found
  end

  test "show attaches the session's published assessments to their participants" do
    sign_in_as(@admin)
    get api_v1_training_session_path(training_sessions(:one))

    assert_response :success
    participants = JSON.parse(response.body)["training_session_participants"]
    pedro = participants.find do |participant|
      participant["player_profile_id"] == player_profiles(:pedro_player).id
    end
    assert pedro.present?
    # Only the published row: pedro's draft and the withdrawn row never leak.
    assert_equal [ assessments(:skill_active).id ], pedro["assessments"].map { |row| row["id"] }

    john = participants.find do |participant|
      participant["player_profile_id"] == player_profiles(:john_player).id
    end
    assert_equal [], john["assessments"]
  end
end
