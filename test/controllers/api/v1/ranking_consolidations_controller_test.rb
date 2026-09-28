require "test_helper"

# Request tests for the Ranking Consolidations API (phase 4): immutable
# snapshots merging several coaches' published session rankings.
class Api::V1::RankingConsolidationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:six)      # coach account linked to maria_coach
    @trainer = users(:three)  # coach role, but not the coach of record
    @admin = users(:two)      # oversight and content creator
    @curator = users(:four)   # oversight only, never a content creator
    @player_user = users(:one)

    @coach = coach_profiles(:maria_coach)
    @definition = assessment_definitions(:balanced)
    @john = player_profiles(:john_player)
    @pedro = player_profiles(:pedro_player)
  end

  # --- helpers ---------------------------------------------------------------

  def json
    JSON.parse(response.body)
  end

  def post_json(path, payload)
    post path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def patch_json(path, payload)
    patch path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def session_path(record)
    "/api/v1/assessment_sessions/#{record.respond_to?(:id) ? record.id : record}"
  end

  def create_draft_session(name:, coach: @coach)
    post_json "/api/v1/assessment_sessions", assessment_session: {
      name: name,
      assessment_definition_id: @definition.id,
      coach_profile_id: coach.id,
      scheduled_on: 3.days.from_now.to_date.iso8601
    }
    assert_response :created
    json["assessment_session"]["id"]
  end

  def add_players!(session_id, players)
    post_json "#{session_path(session_id)}/add_players", players: players
    assert_response :created
    json["assessment_session"]
  end

  def category_cells(values, scale: "one_to_ten")
    @definition.assessment_categories.order(:position, :id).map.with_index do |category, index|
      { assessment_category_id: category.id, scale: scale, value: values[index] }
    end
  end

  # Cells are supplied fully-formed so a test can score a session against a
  # definition other than `@definition`.
  def put_scores!(session_id, cells_by_player)
    put "#{session_path(session_id)}/scores",
        params: { scores: cells_by_player.map { |player_id, cells|
          { player_profile_id: player_id, category_scores: cells }
        } }.to_json,
        headers: { "Content-Type" => "application/json" }
    assert_response :success
  end

  def score_session!(session_id, cells_by_player)
    put_scores!(session_id, cells_by_player.transform_values { |values| category_cells(values) })
  end

  def publish_session!(session_id)
    post "#{session_path(session_id)}/publish"
    assert_response :success
  end

  # A published session built at the model layer, for tests that must not carry a
  # signed-in cookie (a guest test) or must not go through the API.
  def build_published_session_record(name)
    AssessmentSession.create!(
      name: name,
      assessment_definition: @definition,
      coach_profile: @coach,
      created_by: users(:six),
      status: "published",
      published_at: Time.current,
      scheduled_on: Date.current
    )
  end

  def withdraw_session!(session_id)
    post "#{session_path(session_id)}/withdraw"
    assert_response :success
  end

  # Reads a ranking's rows straight from the API, for asserting the state *after* a
  # refused call — a 403 body is not the ranking, so the ranking has to be re-read to
  # show that the refusal changed nothing.
  def json_rows_for(consolidation_id)
    get "/api/v1/ranking_consolidations/#{consolidation_id}"
    assert_response :success
    json["ranking_consolidation"]["rows"]
  end

  # A published session built at the model layer, for tests that must not carry a
  # signed-in cookie (a guest test) or must not go through the API.
  def build_published_session_record(name)
    AssessmentSession.create!(
      name: name,
      assessment_definition: @definition,
      coach_profile: @coach,
      created_by: users(:six),
      status: "published",
      published_at: Time.current,
      scheduled_on: Date.current
    )
  end

  # Two fully-scored, published sessions sharing the definition. Session A
  # ranks john 80 / pedro 70; session B ranks john 60 / pedro 70.
  # Consolidated: john avg 70, pedro avg 70 → tied rank 1, both coverage 2.
  def two_published_sessions
    sign_in_as(@owner)
    first = create_draft_session(name: "First screening")
    add_players!(first, [ { player_profile_id: @john.id }, { player_profile_id: @pedro.id } ])
    score_session!(first, { @john.id => [ 8, 7, 9 ], @pedro.id => [ 7, 6, 8 ] })
    publish_session!(first)

    second = create_draft_session(name: "Second screening")
    add_players!(second, [ { player_profile_id: @john.id }, { player_profile_id: @pedro.id } ])
    score_session!(second, { @john.id => [ 6, 5, 7 ], @pedro.id => [ 7, 6, 8 ] })
    publish_session!(second)

    [ first, second ]
  end

  def create_consolidation(definition_id: @definition.id, session_ids:, name: "Club ranking")
    post_json "/api/v1/ranking_consolidations", ranking_consolidation: {
      name: name,
      assessment_definition_id: definition_id,
      assessment_session_ids: session_ids
    }
  end
  # --- index / show ----------------------------------------------------------

  test "index requires authentication" do
    get "/api/v1/ranking_consolidations"
    assert_response :unauthorized
  end

  test "index refuses a player-role user" do
    sign_in_as(@player_user)
    get "/api/v1/ranking_consolidations"
    assert_response :forbidden
  end

  test "index lists consolidations to a training manager" do
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    assert_response :created

    get "/api/v1/ranking_consolidations"
    assert_response :success
    assert_equal 1, json["ranking_consolidations"].size
    entry = json["ranking_consolidations"].first
    assert_equal "Club ranking", entry["name"]
    assert_equal 2, entry["session_count"]
    assert_equal 2, entry["player_count"]
  end

  test "show returns the frozen snapshot with per-session scores" do
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    assert_response :created
    id = json["ranking_consolidation"]["id"]

    get "/api/v1/ranking_consolidations/#{id}"
    assert_response :success
    body = json["ranking_consolidation"]

    assert_equal 2, body["assessment_sessions"].size
    assert_equal 2, body["rows"].size

    rows = body["rows"].to_h { |row| [ row["player_profile_id"], row ] }
    assert_equal 1, rows[@john.id]["rank"]
    assert_equal 1, rows[@pedro.id]["rank"]
    assert_equal 70, rows[@john.id]["average_score"]
    assert_equal 70, rows[@pedro.id]["average_score"]
    assert_equal 2, rows[@john.id]["coverage"]
    assert_equal first.to_s, rows[@john.id]["coach_scores"].keys.min
  end

  # --- create ----------------------------------------------------------------

  test "a guest cannot create a consolidation" do
    post_json "/api/v1/ranking_consolidations", ranking_consolidation: {
      assessment_definition_id: @definition.id, assessment_session_ids: []
    }
    assert_response :unauthorized
  end

  test "a player cannot create a consolidation" do
    sign_in_as(@player_user)
    create_consolidation(session_ids: [])
    assert_response :forbidden
  end

  test "a curator may view but never create a consolidation" do
    first, second = two_published_sessions

    sign_in_as(@curator)
    create_consolidation(session_ids: [ first, second ])
    assert_response :forbidden

    get "/api/v1/ranking_consolidations"
    assert_response :success
  end
  test "create accepts a draft session; the consolidation starts as a draft" do
    sign_in_as(@owner)
    draft = create_draft_session(name: "Unfinished")
    add_players!(draft, [ { player_profile_id: @john.id } ])

    assert_difference -> { RankingConsolidation.count }, 1 do
      create_consolidation(session_ids: [ draft ])
    end

    # A club ranking is assembled from work still in progress; it is only frozen
    # once every source is published.
    assert_response :created
    assert_equal "draft", json["ranking_consolidation"]["status"]
    assert_equal 1, json["ranking_consolidation"]["unpublished_session_count"]
  end

  test "create refuses sessions on a different definition" do
    sign_in_as(@owner)
    other_definition = AssessmentDefinition.create!(
      name: "Other rubric", status: "active", created_by: @owner,
      assessment_categories_attributes: [
        { category_id: categories(:assessment_rubric).id, weight: 100, position: 0 }
      ]
    )
    other = create_draft_session(name: "Other session")
    # Re-point the draft at the other definition directly: the create endpoint
    # only accepts the active balanced definition in this setup.
    AssessmentSession.find(other).update_column(:assessment_definition_id, other_definition.id)
    add_players!(other, [ { player_profile_id: @john.id } ])
    # Score against the *other* definition's single category, so the session is
    # genuinely complete and the only thing wrong with it is its definition.
    other_category = other_definition.assessment_categories.order(:position, :id).first
    put_scores!(other, { @john.id => [ { assessment_category_id: other_category.id,
                                         scale: "one_to_ten", value: 8 } ] })
    publish_session!(other)

    create_consolidation(session_ids: [ other ])
    assert_response :unprocessable_entity
    assert_match(/different assessment definition/, json["errors"].join(" "))
    assert_equal 0, RankingConsolidation.count
  end

  # `publish` already refuses an incomplete roster, so a normally-produced
  # published session is always complete. This guard covers data that drifts
  # *after* publish (an out-of-band edit, an import, a future scoring change).
  # D21 is a never-block policy: rather than refusing, the consolidation records
  # the affected session and players in `source_warnings`, and the incomplete
  # player is absent from the ranking rather than scored zero.
  test "create merges a published session whose scores drifted incomplete, and records why" do
    sign_in_as(@owner)
    session_id = create_draft_session(name: "Drifted after publish")
    add_players!(session_id, [ { player_profile_id: @john.id }, { player_profile_id: @pedro.id } ])
    score_session!(session_id, { @john.id => [ 8, 7, 9 ], @pedro.id => [ 7, 6, 8 ] })
    publish_session!(session_id)

    # Drop one of pedro's category score rows behind the app's back. (Blanking
    # the score instead would be rejected by the score-pair check constraint.)
    pedro_assessment = AssessmentSession.find(session_id).assessments
                                                .find_by(player_profile_id: @pedro.id)
    AssessmentCategoryScore.where(assessment_id: pedro_assessment.id)
                           .order(:assessment_category_id)
                           .first
                           .delete

    create_consolidation(session_ids: [ session_id ])
    assert_response :created
    assert_equal 1, RankingConsolidation.count

    consolidation = json["ranking_consolidation"]

    # The reason the merge proceeded is stored on the snapshot itself...
    warnings = consolidation["source_warnings"]
    assert_equal 1, warnings.size
    assert_equal session_id, warnings.first["assessment_session_id"]
    assert_equal "Drifted after publish", warnings.first["name"]
    assert_equal 1, warnings.first["incomplete_count"]
    assert_includes warnings.first["incomplete_players"], @pedro.full_name

    # ...and mirrored onto the source column so the table can badge it.
    source = consolidation["assessment_sessions"].first
    assert_equal 1, source["incomplete_count"]
    assert_includes source["incomplete_players"], @pedro.full_name

    # pedro is absent from the ranking entirely, never filled in with zero (D14).
    ranked_ids = consolidation["rows"].map { |row| row["player_profile_id"] }
    assert_includes ranked_ids, @john.id
    refute_includes ranked_ids, @pedro.id
    assert_equal 1, consolidation["player_count"]
  end

  test "a fully scored draft session is accepted and merged as usual" do
    sign_in_as(@owner)
    session_id = create_draft_session(name: "Still a draft")
    add_players!(session_id, [ { player_profile_id: @john.id } ])
    score_session!(session_id, { @john.id => [ 8, 7, 9 ] })

    # How well a draft is scored is irrelevant to whether it may be consolidated:
    # only *publishing* is gated, so the merge itself is identical either way.
    create_consolidation(session_ids: [ session_id ])
    assert_response :created
    assert_equal "draft", json["ranking_consolidation"]["status"]
    assert_equal 1, json["ranking_consolidation"]["player_count"]
  end

  # --- publish --------------------------------------------------------------

  test "a draft is refused while any source session is still a draft" do
    sign_in_as(@owner)
    draft = create_draft_session(name: "Still a draft")
    add_players!(draft, [ { player_profile_id: @john.id } ])
    score_session!(draft, { @john.id => [ 8, 7, 9 ] })
    create_consolidation(session_ids: [ draft ])
    assert_response :created
    id = json["ranking_consolidation"]["id"]

    post "/api/v1/ranking_consolidations/#{id}/publish"

    assert_response :unprocessable_entity
    # The message names the session, so the coach knows what to go and finish.
    assert_match(/Still a draft/, json["errors"].join(" "))
    assert_predicate RankingConsolidation.find(id), :draft?
  end

  test "publishing freezes the ranking once every source is published" do
    sign_in_as(@owner)
    draft = create_draft_session(name: "Will be finished")
    add_players!(draft, [ { player_profile_id: @john.id } ])
    score_session!(draft, { @john.id => [ 8, 7, 9 ] })
    create_consolidation(session_ids: [ draft ])
    id = json["ranking_consolidation"]["id"]

    publish_session!(draft)
    post "/api/v1/ranking_consolidations/#{id}/publish"

    assert_response :success
    assert_equal "published", json["ranking_consolidation"]["status"]
    assert json["ranking_consolidation"]["published_at"].present?
    assert_equal 0, json["ranking_consolidation"]["unpublished_session_count"]
  end

  # The point of re-deriving at publish: a draft session's scores move on, and
  # freezing the snapshot taken at build time would publish a club ranking that
  # disagrees with the session behind it.
  test "publishing re-derives the ranking from the sessions' current scores" do
    sign_in_as(@owner)
    draft = create_draft_session(name: "Rescored later")
    add_players!(draft, [ { player_profile_id: @john.id } ])
    score_session!(draft, { @john.id => [ 8, 7, 9 ] })
    create_consolidation(session_ids: [ draft ])
    id = json["ranking_consolidation"]["id"]
    built_score = RankingConsolidation.find(id).rows.first.average_score

    # The coach keeps scoring before finishing the session.
    score_session!(draft, { @john.id => [ 10, 10, 10 ] })
    publish_session!(draft)
    post "/api/v1/ranking_consolidations/#{id}/publish"
    assert_response :success

    # Published against the final scores, not the ones present at build time.
    assert_equal 100, RankingConsolidation.find(id).rows.first.average_score
    refute_equal built_score, RankingConsolidation.find(id).rows.first.average_score
  end

  test "an already published ranking cannot be published again" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"
    assert_response :success

    post "/api/v1/ranking_consolidations/#{id}/publish"

    assert_response :unprocessable_entity
    assert_match(/already published/, json["errors"].join(" "))
  end

  test "a coach who did not author the ranking may not publish it" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]

    sign_in_as(users(:three))
    post "/api/v1/ranking_consolidations/#{id}/publish"

    assert_response :forbidden
    assert_predicate RankingConsolidation.find(id), :draft?
  end

  test "curator and admin may publish a ranking they did not author" do
    [ users(:four), users(:two) ].each do |user|
      sign_in_as(@owner)
      first, second = two_published_sessions
      create_consolidation(session_ids: [ first, second ])
      id = json["ranking_consolidation"]["id"]

      sign_in_as(user)
      post "/api/v1/ranking_consolidations/#{id}/publish"

      assert_response :success
      assert_predicate RankingConsolidation.find(id), :published?
    end
  end

  test "a guest may not publish" do
    # Built from the model layer only. `two_published_sessions` signs in as
    # @owner, and a session cookie set anywhere in the test persists — so
    # anything routed through those helpers would silently stop being a guest
    # test and pass for the wrong reason.
    session = assessment_sessions(:published_squad)
    consolidation = RankingConsolidationBuilder.new(
      assessment_definition: session.assessment_definition,
      session_ids: [ session.id ]
    ).call

    post "/api/v1/ranking_consolidations/#{consolidation.id}/publish"

    assert_response :unauthorized
    assert_predicate consolidation.reload, :draft?
  end

  # --- withdraw / restore ----------------------------------------------------

  test "the author withdraws their own published ranking" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"
    assert_response :success

    post "/api/v1/ranking_consolidations/#{id}/withdraw"

    assert_response :success
    consolidation = RankingConsolidation.find(id)
    assert_predicate consolidation, :withdrawn?
    assert_nil consolidation.published_at
    # The rows survive: history keeps the record that this ranking existed, it just
    # loses the claim to be current.
    assert consolidation.rows.any?
  end

  test "a coach who did not author the ranking may not withdraw it" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"

    sign_in_as(users(:three))
    post "/api/v1/ranking_consolidations/#{id}/withdraw"

    assert_response :forbidden
    assert_predicate RankingConsolidation.find(id), :published?
  end

  test "a curator may withdraw a ranking they did not author" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"

    sign_in_as(users(:four))
    post "/api/v1/ranking_consolidations/#{id}/withdraw"

    assert_response :success
    assert_predicate RankingConsolidation.find(id), :withdrawn?
  end

  test "a draft ranking cannot be withdrawn" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]

    post "/api/v1/ranking_consolidations/#{id}/withdraw"

    assert_response :unprocessable_entity
    assert_predicate RankingConsolidation.find(id), :draft?
  end

  # --- edit / destroy --------------------------------------------------------

  test "the author edits the name and notes of their own draft" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]

    patch_json "/api/v1/ranking_consolidations/#{id}", ranking_consolidation: {
      name: "Autumn ranking (revised)", notes: "Adds the late screening"
    }

    assert_response :success
    consolidation = RankingConsolidation.find(id)
    assert_equal "Autumn ranking (revised)", consolidation.name
    assert_equal "Adds the late screening", consolidation.notes
  end

  test "a draft ranking cannot have its rubric swapped" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    definition_before = RankingConsolidation.find(id).assessment_definition_id

    patch_json "/api/v1/ranking_consolidations/#{id}", ranking_consolidation: {
      name: "Renamed", assessment_definition_id: 999_999
    }

    # Strong params simply do not accept it: a consolidation describes one merge
    # over a fixed set of sessions, and swapping the rubric underneath would make
    # the record describe a merge it never performed.
    assert_response :success
    consolidation = RankingConsolidation.find(id)
    assert_equal "Renamed", consolidation.name
    assert_equal definition_before, consolidation.assessment_definition_id
  end

  test "a published ranking cannot be edited, not even by its author" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"
    assert_response :success

    patch_json "/api/v1/ranking_consolidations/#{id}", ranking_consolidation: { name: "Rewritten" }

    assert_response :unprocessable_entity
    refute_equal "Rewritten", RankingConsolidation.find(id).name
  end

  test "a coach who did not author a draft ranking may not edit or delete it" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    sign_in_as(users(:three))

    patch_json "/api/v1/ranking_consolidations/#{id}", ranking_consolidation: { name: "Hijacked" }
    assert_response :forbidden

    assert_no_difference -> { RankingConsolidation.count } do
      delete "/api/v1/ranking_consolidations/#{id}"
    end
    assert_response :forbidden
  end

  test "the author deletes their own draft ranking" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]

    assert_difference -> { RankingConsolidation.count }, -1 do
      delete "/api/v1/ranking_consolidations/#{id}"
    end

    assert_response :success
  end

  test "an admin may delete a published ranking" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"
    assert_response :success

    sign_in_as(users(:two))
    assert_difference -> { RankingConsolidation.count }, -1 do
      delete "/api/v1/ranking_consolidations/#{id}"
    end

    assert_response :success
  end

  test "a curator and a non-authoring coach may not delete a published ranking" do
    [ users(:four), users(:three) ].each do |user|
      sign_in_as(@owner)
      first, second = two_published_sessions
      create_consolidation(session_ids: [ first, second ])
      id = json["ranking_consolidation"]["id"]
      post "/api/v1/ranking_consolidations/#{id}/publish"

      sign_in_as(user)
      assert_no_difference -> { RankingConsolidation.count } do
        delete "/api/v1/ranking_consolidations/#{id}"
      end
      assert_response :forbidden
    end
  end

  test "an admin restores a withdrawn ranking to draft" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"
    post "/api/v1/ranking_consolidations/#{id}/withdraw"
    assert_predicate RankingConsolidation.find(id), :withdrawn?

    sign_in_as(users(:two))
    post_json "/api/v1/ranking_consolidations/#{id}/restore", to_status: "draft"

    assert_response :success
    assert_predicate RankingConsolidation.find(id), :draft?
  end

  test "an admin restores a withdrawn ranking to published, re-deriving it" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"
    post "/api/v1/ranking_consolidations/#{id}/withdraw"
    assert_predicate RankingConsolidation.find(id), :withdrawn?

    sign_in_as(users(:two))
    post_json "/api/v1/ranking_consolidations/#{id}/restore", to_status: "published"

    assert_response :success
    assert_predicate RankingConsolidation.find(id), :published?
  end

  test "the author may not restore their own withdrawn ranking" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"
    post "/api/v1/ranking_consolidations/#{id}/withdraw"

    post_json "/api/v1/ranking_consolidations/#{id}/restore", to_status: "draft"

    # A retraction its own author could quietly undo would not be a retraction.
    assert_response :forbidden
    assert_predicate RankingConsolidation.find(id), :withdrawn?
  end

  test "a withdrawn ranking can be neither re-withdrawn nor published" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"
    post "/api/v1/ranking_consolidations/#{id}/withdraw"
    assert_predicate RankingConsolidation.find(id), :withdrawn?

    # Re-withdrawing: the author passes the authority test, so this exercises the
    # status gate on its own.
    post "/api/v1/ranking_consolidations/#{id}/withdraw"
    assert_response :unprocessable_entity

    post "/api/v1/ranking_consolidations/#{id}/publish"
    assert_response :unprocessable_entity
    assert_predicate RankingConsolidation.find(id), :withdrawn?
  end

  # A withdrawn source is excluded from the merge, not refused. The consolidation
  # still lists it, still says why, and still publishes over the rest.
  test "a withdrawn source no longer blocks publishing and is excluded from the ranking" do
    sign_in_as(@owner)
    first = create_draft_session(name: "First screening")
    add_players!(first, [ { player_profile_id: @john.id }, { player_profile_id: @pedro.id } ])
    score_session!(first, { @john.id => [ 8, 7, 9 ], @pedro.id => [ 7, 6, 8 ] })
    publish_session!(first)

    second = create_draft_session(name: "Then withdrawn")
    add_players!(second, [ { player_profile_id: @john.id } ])
    score_session!(second, { @john.id => [ 2, 2, 2 ] })
    publish_session!(second)

    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]

    withdraw_session!(second)
    post "/api/v1/ranking_consolidations/#{id}/publish"

    assert_response :success
    consolidation = RankingConsolidation.find(id)
    assert_predicate consolidation, :published?

    # Still listed as a source — not silently dropped — but contributing nothing.
    assert_equal 2, consolidation.assessment_sessions.count
    empty = consolidation.consolidation_sessions.find_by(assessment_session_id: second)
    assert_empty empty.ranking_snapshot

    # The withdrawn session's 2s must not pull John's average down.
    john = consolidation.rows.find_by(player_profile_id: @john.id)
    assert_equal 80, john.average_score
    # Coverage is measured against *contributing* sessions, so a player is not
    # reported as under-covered because of a session its author retracted.
    assert_equal 1, john.coverage
  end

  test "a withdrawn source is reported so the coach can see it was excluded" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    withdraw_session!(second)

    get "/api/v1/ranking_consolidations/#{id}"

    assert_response :success
    assert_equal 1, json["ranking_consolidation"]["withdrawn_session_count"]
    withdrawn = json["ranking_consolidation"]["assessment_sessions"]
                       .find { |s| s["assessment_session_id"] == second }
    assert_equal "withdrawn", withdrawn["status"]
  end

  test "a ranking whose every source was withdrawn cannot be published" do
    sign_in_as(@owner)
    only = create_draft_session(name: "The only one")
    add_players!(only, [ { player_profile_id: @john.id } ])
    score_session!(only, { @john.id => [ 8, 7, 9 ] })
    publish_session!(only)
    create_consolidation(session_ids: [ only ])
    id = json["ranking_consolidation"]["id"]
    withdraw_session!(only)

    post "/api/v1/ranking_consolidations/#{id}/publish"

    # Nothing is left to rank, so this is refused — rather than published as an
    # empty ranking that would read as "nobody was scored".
    assert_response :unprocessable_entity
    assert_match(/nothing to rank/, json["errors"].join(" "))
    assert_predicate RankingConsolidation.find(id), :draft?
  end

  # --- recalculate -----------------------------------------------------------
  #
  # Withdrawing a source does not cascade: a published ranking keeps its figures, so a
  # source retracted afterwards is still counted until somebody deliberately corrects
  # it. These pin both halves of that promise — the default (immutable) and the
  # explicit exception.

  # Publishes a ranking over two sessions, then withdraws the second *after*
  # publication. The publication is stamped in the past with `travel_to` so the
  # withdrawal genuinely lands later than it — otherwise both events share one
  # millisecond and the ordering the whole feature depends on becomes a race.
  def published_ranking_with_late_withdrawal
    sign_in_as(@owner)
    first = create_draft_session(name: "January")
    add_players!(first, [ { player_profile_id: @john.id } ])
    score_session!(first, { @john.id => [ 8, 7, 9 ] })
    publish_session!(first)

    second = create_draft_session(name: "September")
    add_players!(second, [ { player_profile_id: @john.id } ])
    score_session!(second, { @john.id => [ 2, 2, 2 ] })
    publish_session!(second)

    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    travel_to(2.hours.ago) do
      post "/api/v1/ranking_consolidations/#{id}/publish"
      assert_response :success
    end

    # Retracted at the real "now", a clear two hours after the ranking was frozen.
    withdraw_session!(second)
    id
  end

  test "a source withdrawn after publication is still counted and is reported as such" do
    id = published_ranking_with_late_withdrawal

    get "/api/v1/ranking_consolidations/#{id}"

    assert_response :success
    payload = json["ranking_consolidation"]
    # The 2s are still in John's average (80 from January, 20 from September), and
    # coverage is 2 because both sessions genuinely still contribute — which is
    # precisely why the retracted session cannot be described as excluded.
    john = payload["rows"].find { |r| r["player_profile_id"] == @john.id }
    assert_equal 50, john["average_score"]
    assert_equal 2, john["coverage"]

    assert_equal 1, payload["stale_withdrawn_session_count"]
    assert_equal 0, payload["excluded_withdrawn_session_count"]
    assert_equal payload["published_at"], payload["computed_at"]
    assert_nil payload["recalculated_at"]

    # Listed as still included, so the UI never claims to have dropped scores that
    # are in fact on screen.
    withdrawn = payload["assessment_sessions"].find { |s| s["name"] == "September" }
    assert_equal "withdrawn", withdrawn["status"]
    assert withdrawn["included_in_ranking"]
    assert_not_nil withdrawn["withdrawn_at"]
  end

  test "recalculating excludes the withdrawn source from a published ranking" do
    id = published_ranking_with_late_withdrawal

    sign_in_as(@curator)
    post "/api/v1/ranking_consolidations/#{id}/recalculate"

    assert_response :success
    payload = json["ranking_consolidation"]

    # The 2s are gone: John's average is January alone, and coverage drops to the one
    # session that actually contributed — the denominator moves with the data.
    john = payload["rows"].find { |r| r["player_profile_id"] == @john.id }
    assert_equal 80, john["average_score"]
    assert_equal 1, john["coverage"]

    # Still the same published ranking — the source stays attached, it just stops
    # contributing, so history keeps showing September was ever part of this.
    assert_equal "published", payload["status"]
    assert_equal 2, payload["assessment_sessions"].size
    withdrawn = payload["assessment_sessions"].find { |s| s["name"] == "September" }
    assert_not withdrawn["included_in_ranking"]

    # The publication date is untouched; the correction carries its own stamp.
    assert_not_nil payload["published_at"]
    assert_operator Time.parse(payload["recalculated_at"].to_s),
                    :>, Time.parse(payload["published_at"].to_s)
    assert_equal @curator.id, payload["recalculated_by_id"]
    assert_equal 0, payload["stale_withdrawn_session_count"]
    assert_equal 1, payload["excluded_withdrawn_session_count"]
    assert_not payload["recalculable"]
    assert_not payload["can_recalculate"]
  end

  # --- a source restored to published -----------------------------------------
  #
  # The mirror of the late withdrawal: the snapshot is *missing* scores it should
  # have. Without a notice and an action, the ranking under-reports in silence while
  # the API claims the session is included.

  # Publishes over two sessions, withdraws the second before the freeze so the merge
  # excludes it, then puts it back to published — the sequence a real retraction and
  # admin restore produce.
  def published_ranking_with_restored_source
    sign_in_as(@owner)
    first = create_draft_session(name: "January")
    add_players!(first, [ { player_profile_id: @john.id } ])
    score_session!(first, { @john.id => [ 8, 7, 9 ] })
    publish_session!(first)

    second = create_draft_session(name: "Retracted, then restored")
    add_players!(second, [ { player_profile_id: @john.id } ])
    score_session!(second, { @john.id => [ 6, 5, 7 ] })
    publish_session!(second)

    # Withdrawn before the ranking is frozen, so the merge skips it.
    withdraw_session!(second)
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"
    assert_response :success

    # Admin-only session restore, back to published.
    sign_in_as(@admin)
    post "/api/v1/assessment_sessions/#{second}/restore", params: { to_status: "published" }.to_json,
                                                            headers: { "Content-Type" => "application/json" }
    assert_response :success
    id
  end

  test "a source restored to published is reported as missing from the ranking" do
    id = published_ranking_with_restored_source

    get "/api/v1/ranking_consolidations/#{id}"

    assert_response :success
    payload = json["ranking_consolidation"]
    assert_equal 1, payload["restored_session_count"]
    # Nothing is withdrawn any more, so the withdrawn counters are both zero.
    assert_equal 0, payload["stale_withdrawn_session_count"]
    assert_equal 0, payload["excluded_withdrawn_session_count"]
    # But the ranking really is out of date, so the action is offered to oversight.
    assert payload["recalculable"]

    restored = payload["assessment_sessions"].find { |s| s["name"] == "Retracted, then restored" }
    assert_equal "published", restored["status"]
    # The critical assertion: it is *not* included, because the snapshot is empty.
    # Reporting `true` here is the bug — the screen would claim a ranking that
    # demonstrably does not contain these scores.
    assert_not restored["included_in_ranking"]
  end

  test "recalculating includes a restored source and then reports nothing to do" do
    id = published_ranking_with_restored_source

    # Coverage of 1 before: the ranking rests on January alone.
    assert_equal 1, json_rows_for(id).first["coverage"]

    post "/api/v1/ranking_consolidations/#{id}/recalculate"

    assert_response :success
    payload = json["ranking_consolidation"]
    assert_equal 2, payload["rows"].first["coverage"]
    assert_equal 0, payload["restored_session_count"]
    # The action is spent, so the UI has nothing left to offer.
    assert_not payload["recalculable"]
    assert_not payload["can_recalculate"]
  end

  test "a plain coach is told a restored source is out rather than offered the fix" do
    id = published_ranking_with_restored_source

    sign_in_as(@owner)
    get "/api/v1/ranking_consolidations/#{id}"

    payload = json["ranking_consolidation"]
    assert payload["recalculable"]
    assert_not payload["can_recalculate"]
  end

  test "a guest may not withdraw a ranking" do
    # Built through the model layer only. A session cookie set anywhere in a test
    # persists for the rest of it, so anything routed through a signing-in helper
    # would silently stop being a guest test — including `two_published_sessions`,
    # which signs in as @owner.
    first = build_published_session_record("First screening")
    second = build_published_session_record("Second screening")
    consolidation = RankingConsolidationBuilder.new(
      assessment_definition: @definition, session_ids: [ first.id, second.id ]
    ).call
    # Published at the model layer too, since publish is author-gated as well.
    RankingConsolidationPublisher.new(consolidation).call
    assert_predicate consolidation.reload, :published?

    post "/api/v1/ranking_consolidations/#{consolidation.id}/withdraw"

    assert_response :unauthorized
  end

  test "an admin may recalculate, and the action is not offered a second time" do
    id = published_ranking_with_late_withdrawal

    sign_in_as(@admin)
    post "/api/v1/ranking_consolidations/#{id}/recalculate"
    assert_response :success

    post "/api/v1/ranking_consolidations/#{id}/recalculate"

    # Refused: the correction is spent, and rewriting identical figures would be churn.
    assert_response :unprocessable_entity
    assert_match(/nothing to recalculate/, json["errors"].join(" "))
  end

  test "the author may not recalculate their own published ranking" do
    id = published_ranking_with_late_withdrawal

    # @owner built and published it and could withdraw their own session — but
    # rewriting a published result is oversight work, not the author's own call.
    sign_in_as(@owner)
    post "/api/v1/ranking_consolidations/#{id}/recalculate"

    assert_response :forbidden
    # Refused means unchanged: the retracted session is still counted.
    john = json_rows_for(id).find { |r| r["player_profile_id"] == @john.id }
    assert_equal 50, john["average_score"]
  end

  test "a coach who is neither author nor curator may not recalculate" do
    id = published_ranking_with_late_withdrawal

    sign_in_as(@trainer)
    post "/api/v1/ranking_consolidations/#{id}/recalculate"

    assert_response :forbidden
  end

  test "only oversight is offered the recalculate action" do
    id = published_ranking_with_late_withdrawal

    sign_in_as(@curator)
    get "/api/v1/ranking_consolidations/#{id}"
    assert json["ranking_consolidation"]["recalculable"]
    assert json["ranking_consolidation"]["can_recalculate"]

    sign_in_as(@owner)
    get "/api/v1/ranking_consolidations/#{id}"
    # The situation is real, but this caller may not act on it, so the button is
    # hidden rather than shown and then refused.
    assert json["ranking_consolidation"]["recalculable"]
    assert_not json["ranking_consolidation"]["can_recalculate"]
  end

  test "a guest may not recalculate" do
    # Built at the model layer for the same reason as the guest withdraw test: a
    # cookie set by any helper would quietly stop this being a guest test.
    first = build_published_session_record("January")
    second = build_published_session_record("September")
    consolidation = RankingConsolidationBuilder.new(
      assessment_definition: @definition, session_ids: [ first.id, second.id ]
    ).call
    RankingConsolidationPublisher.new(consolidation).call
    second.update!(status: "withdrawn", updated_at: 1.hour.from_now)
    assert_predicate consolidation.reload, :recalculable?

    post "/api/v1/ranking_consolidations/#{consolidation.id}/recalculate"

    assert_response :unauthorized
  end

  test "a draft is never offered recalculation, since it re-derives at publish" do
    sign_in_as(@owner)
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]

    get "/api/v1/ranking_consolidations/#{id}"

    assert_not json["ranking_consolidation"]["recalculable"]
    assert_not json["ranking_consolidation"]["can_recalculate"]
  end

  test "a source withdrawn before publication leaves nothing to recalculate" do
    sign_in_as(@owner)
    first = create_draft_session(name: "January")
    add_players!(first, [ { player_profile_id: @john.id } ])
    score_session!(first, { @john.id => [ 8, 7, 9 ] })
    publish_session!(first)

    second = create_draft_session(name: "Retracted early")
    add_players!(second, [ { player_profile_id: @john.id } ])
    score_session!(second, { @john.id => [ 2, 2, 2 ] })
    publish_session!(second)

    # Retracted *before* the ranking is published, so the merge already skipped it.
    withdraw_session!(second)
    create_consolidation(session_ids: [ first, second ])
    id = json["ranking_consolidation"]["id"]
    post "/api/v1/ranking_consolidations/#{id}/publish"
    assert_response :success

    sign_in_as(@curator)
    get "/api/v1/ranking_consolidations/#{id}"

    assert_equal 0, json["ranking_consolidation"]["stale_withdrawn_session_count"]
    assert_equal 1, json["ranking_consolidation"]["excluded_withdrawn_session_count"]
    assert_not json["ranking_consolidation"]["recalculable"]

    post "/api/v1/ranking_consolidations/#{id}/recalculate"
    assert_response :unprocessable_entity
    assert_match(/nothing to recalculate/, json["errors"].join(" "))
  end

  test "a withdrawn ranking is restored, not recalculated" do
    id = published_ranking_with_late_withdrawal
    sign_in_as(@curator)
    post "/api/v1/ranking_consolidations/#{id}/withdraw"
    assert_response :success

    post "/api/v1/ranking_consolidations/#{id}/recalculate"

    assert_response :unprocessable_entity
    assert_match(/restored/, json["errors"].join(" "))
  end

  test "create reports an unknown session id without writing anything" do
    sign_in_as(@owner)
    first, _second = two_published_sessions

    create_consolidation(session_ids: [ first, 999_999 ])
    assert_response :unprocessable_entity
    assert_match(/not found/, json["errors"].join(" "))
    assert_equal 0, RankingConsolidation.count
  end

  test "create requires at least one session" do
    sign_in_as(@owner)
    create_consolidation(session_ids: [])
    assert_response :unprocessable_entity
    assert_equal 0, RankingConsolidation.count
  end

  test "a partially overlapping roster averages over covered sessions only" do
    sign_in_as(@owner)
    first = create_draft_session(name: "Both players")
    add_players!(first, [ { player_profile_id: @john.id }, { player_profile_id: @pedro.id } ])
    score_session!(first, { @john.id => [ 8, 7, 9 ], @pedro.id => [ 7, 6, 8 ] })
    publish_session!(first)

    second = create_draft_session(name: "John only")
    add_players!(second, [ { player_profile_id: @john.id } ])
    score_session!(second, { @john.id => [ 6, 5, 7 ] })
    publish_session!(second)

    create_consolidation(session_ids: [ first, second ])
    assert_response :created
    rows = json["ranking_consolidation"]["rows"].to_h { |row| [ row["player_profile_id"], row ] }

    # john: (80 + 60) / 2 = 70 over 2 sessions; pedro: 70 over 1 session.
    # Same average → shared rank, and pedro's coverage says 1, never a zero
    # from the session he was not part of.
    assert_equal 70, rows[@john.id]["average_score"]
    assert_equal 70, rows[@pedro.id]["average_score"]
    assert_equal 2, rows[@john.id]["coverage"]
    assert_equal 1, rows[@pedro.id]["coverage"]
    assert_equal 1, rows[@john.id]["rank"]
    assert_equal 1, rows[@pedro.id]["rank"]
  end

  test "withdrawing a source session leaves the consolidation unchanged" do
    first, second = two_published_sessions
    create_consolidation(session_ids: [ first, second ])
    assert_response :created
    id = json["ranking_consolidation"]["id"]
    before = json["ranking_consolidation"]["rows"]

    AssessmentSession.find(first).update!(status: "withdrawn")

    get "/api/v1/ranking_consolidations/#{id}"
    assert_response :success
    assert_equal before, json["ranking_consolidation"]["rows"]
  end
end
