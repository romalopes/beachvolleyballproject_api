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

  # Score every category of the definition for one player, which is what makes a
  # session's ranking non-empty. Used to prove a re-derivation actually sees new
  # numbers rather than replaying the old snapshot.
  def rescore_session(session, player_id:, values:)
    result = session.assessments.find_or_initialize_by(player_profile_id: player_id)
    result.coach_profile = @coach
    result.assessment_definition = @definition
    result.created_by = @creator
    result.status = "draft"
    result.save!
    @definition.assessment_categories.ordered.each_with_index do |category, index|
      row = result.assessment_category_scores.find_or_initialize_by(
        assessment_category: category
      )
      row.scale = "one_to_ten"
      row.value = values[index]
      row.save!
    end
    result
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

  test "a draft session is merged, and the result is a draft consolidation" do
    draft = build_published_session(name: "Draft", player_ids: [ @john.id ])
    rescore_session(draft, player_id: @john.id, values: [ 8, 7, 9 ])
    draft.update!(status: "draft", published_at: nil)

    consolidation = build(session_ids: [ draft.id ])

    # Publication is gated, not construction: a club ranking is assembled from
    # work in progress and frozen later.
    assert_predicate consolidation, :draft?
    assert_nil consolidation.published_at
    assert_equal [ draft.id ], consolidation.assessment_sessions.map(&:id)
  end

  test "refresh! re-derives a draft from the sessions' current scores" do
    draft = build_published_session(name: "Draft", player_ids: [ @john.id ])
    rescore_session(draft, player_id: @john.id, values: [ 8, 7, 9 ])
    draft.update!(status: "draft", published_at: nil)
    consolidation = build(session_ids: [ draft.id ])
    built_score = consolidation.rows.first.average_score

    # The coach keeps scoring the still-draft session.
    rescore_session(draft, player_id: @john.id, values: [ 10, 10, 10 ])

    RankingConsolidationBuilder.new(assessment_definition: @definition)
                               .refresh!(consolidation.reload)

    # A draft's snapshot is not history, so it is rebuilt from the source.
    assert_equal 100, consolidation.rows.reload.first.average_score
    refute_equal built_score, consolidation.rows.first.average_score
  end

  # A withdrawn source is excluded from the merge, not refused: it keeps its place
  # in the consolidation and gets a warning, so the coach sees what was dropped.
  test "a withdrawn session is excluded from the ranking and recorded as such" do
    session = build_published_session(name: "Retracted", player_ids: [ @john.id ])
    rescore_session(session, player_id: @john.id, values: [ 8, 7, 9 ])

    consolidation = build(session_ids: [ session.id ])
    session.update!(status: "withdrawn", published_at: nil)

    RankingConsolidationBuilder.new(assessment_definition: @definition).refresh!(consolidation)

    # Still a source, contributing nothing.
    assert_equal [ session.id ], consolidation.assessment_sessions.map(&:id)
    assert_empty consolidation.rows
    warning = consolidation.source_warnings.find { |w| w["reason"] == "source_session_withdrawn" }
    assert_equal "Retracted", warning["name"]
  end

  test "refresh! refuses to touch a published consolidation" do
    first = build_published_session(name: "First", player_ids: [ @john.id ])
    rescore_session(first, player_id: @john.id, values: [ 8, 7, 9 ])
    second = build_published_session(name: "Second", player_ids: [ @pedro.id ])
    rescore_session(second, player_id: @pedro.id, values: [ 9, 8, 7 ])
    consolidation = build(session_ids: [ first.id, second.id ])
    consolidation.update!(status: "published", published_at: Time.current)

    error = assert_raises(RankingConsolidationBuilder::Error) do
      RankingConsolidationBuilder.new(assessment_definition: @definition)
                                  .refresh!(consolidation)
    end

    assert_match(/cannot be rebuilt/, error.errors.join(" "))
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
