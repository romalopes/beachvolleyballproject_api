require "test_helper"

# Unit tests for RankingConsolidationBuilder (plan §8, D20–D22).
#
# The controller tests exercise the merge end-to-end; these pin the service
# contract itself, above all the ratified D21 policy: a consolidation never
# refuses over missing or incomplete players, assigns nobody zero, and records
# on the snapshot why it merged anyway.
class RankingConsolidationBuilderTest < ActiveSupport::TestCase
  setup do
    @definition = assessment_definitions(:balanced)
    @coach = coach_profiles(:maria_coach)
    @creator = users(:six)
    @john = player_profiles(:john_player)
    @pedro = player_profiles(:pedro_player)
  end

  def build_published_session(name:, player_ids: [])
    session = AssessmentSession.create!(
      name: name,
      assessment_definition: @definition,
      coach_profile: @coach,
      created_by: @creator,
      status: "published",
      published_at: Time.current,
      scheduled_on: Date.current
    )
    player_ids.each do |player_id|
      session.participants.create!(player_profile_id: player_id, inclusion: "included")
    end
    session
  end

  def build(session_ids:, definition: @definition)
    RankingConsolidationBuilder.new(
      assessment_definition: definition,
      session_ids: session_ids
    ).call
  end

  # The policy change: this scenario used to raise and write nothing.
  test "a wholly unscored session merges instead of refusing, naming every player" do
    session = build_published_session(name: "Nobody scored", player_ids: [ @john.id, @pedro.id ])

    consolidation = build(session_ids: [ session.id ])

    assert_equal 1, RankingConsolidation.count
    assert_equal 1, consolidation.source_warnings.size

    warning = consolidation.source_warnings.first
    assert_equal session.id, warning["assessment_session_id"]
    assert_equal "Nobody scored", warning["name"]
    assert_equal 2, warning["incomplete_count"]
    assert_includes warning["incomplete_players"], @john.full_name
    assert_includes warning["incomplete_players"], @pedro.full_name

    # Nothing to rank, but nobody was zero-filled either (D14, D21).
    assert_empty consolidation.rows
    assert_empty consolidation.consolidation_sessions.first.ranking_snapshot
  end

  test "a session with nothing incomplete records no warning" do
    session = build_published_session(name: "Empty roster")

    consolidation = build(session_ids: [ session.id ])

    assert_empty consolidation.source_warnings
    assert_empty consolidation.rows
  end

  test "warnings are ordered by session id so the payload is deterministic" do
    first = build_published_session(name: "First unscored", player_ids: [ @john.id ])
    second = build_published_session(name: "Second unscored", player_ids: [ @pedro.id ])

    # Deliberately pass them in reverse: output order must follow session id,
    # not the caller's list order, so the same selection always serialises alike.
    consolidation = build(session_ids: [ second.id, first.id ])

    assert_equal [ first.id, second.id ],
                 consolidation.source_warnings.map { |warning| warning["assessment_session_id"] }
    assert_equal [ "First unscored", "Second unscored" ],
                 consolidation.source_warnings.map { |warning| warning["name"] }
  end

  test "warnings are stored on the row rather than recomputed from the source" do
    session = build_published_session(name: "Drifted", player_ids: [ @john.id ])
    consolidation = build(session_ids: [ session.id ])

    # A warning written at merge time survives the source changing afterwards —
    # which is the whole point of a snapshot (D24).
    session.participants.destroy_all
    consolidation.reload

    assert_equal 1, consolidation.source_warnings.size
    assert_equal "Drifted", consolidation.source_warnings.first["name"]
    assert_equal [ @john.full_name ], consolidation.source_warnings.first["incomplete_players"]
  end

  # D21 never blocks over *players*, but invalid input is still refused.
  test "an empty selection is refused" do
    error = assert_raises(RankingConsolidationBuilder::Error) { build(session_ids: []) }
    assert_match(/At least one assessment session/, error.errors.join(" "))
    assert_equal 0, RankingConsolidation.count
  end

  test "an unknown session id is refused without writing anything" do
    session = build_published_session(name: "Real")

    error = assert_raises(RankingConsolidationBuilder::Error) do
      build(session_ids: [ session.id, 999_999 ])
    end

    assert_match(/not found/, error.errors.join(" "))
    assert_equal 0, RankingConsolidation.count
  end

  test "a draft session is refused even though a player is unscored" do
    draft = build_published_session(name: "Draft", player_ids: [ @john.id ])
    draft.update!(status: "draft", published_at: nil)

    error = assert_raises(RankingConsolidationBuilder::Error) do
      build(session_ids: [ draft.id ])
    end

    assert_match(/not published/, error.errors.join(" "))
    assert_equal 0, RankingConsolidation.count
  end

  test "a session on another definition is refused" do
    session = build_published_session(name: "Wrong rubric")
    other = assessment_definitions(:pre_season)

    error = assert_raises(RankingConsolidationBuilder::Error) do
      build(session_ids: [ session.id ], definition: other)
    end

    assert_match(/different assessment definition/, error.errors.join(" "))
    assert_equal 0, RankingConsolidation.count
  end
end
