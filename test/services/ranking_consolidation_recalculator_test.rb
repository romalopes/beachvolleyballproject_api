require "test_helper"

# Unit tests for RankingConsolidationRecalculator: the single, supervised exception
# to a published ranking's immutability (D24).
#
# The rule under test is about *time*, not about status. A withdrawal never
# cascades, so what matters is whether the source was already retracted when the
# snapshot was computed:
#
#   withdrawn before  -> the merge already skipped it; nothing to correct
#   withdrawn after   -> its scores are still in the numbers; correcting is optional
#                        and must be explicit
class RankingConsolidationRecalculatorTest < ActiveSupport::TestCase
  setup do
    @definition = assessment_definitions(:balanced)
    @coach = coach_profiles(:maria_coach)
    @creator = users(:six)
    @admin = users(:two)
    @curator = users(:four)
    @john = player_profiles(:john_player)
    @pedro = player_profiles(:pedro_player)
  end

  # --- helpers ---------------------------------------------------------------

  # A published session with John and Pedro scored 8/7/9 and 7/6/8. Scored at the
  # model layer so a test can arrange a publication/withdrawal order the API's
  # author gates would otherwise make awkward to express.
  def published_session(name:)
    session = AssessmentSession.create!(
      name: name, assessment_definition: @definition, coach_profile: @coach,
      created_by: @creator, status: "published", published_at: 3.days.ago,
      scheduled_on: Date.current
    )
    { @john.id => [ 8, 7, 9 ], @pedro.id => [ 7, 6, 8 ] }.each do |player_id, values|
      # A player only appears in a session's ranking if they are a participant, so
      # membership is part of arranging a scoreable session, not an afterthought.
      session.participants.create!(player_profile_id: player_id, inclusion: "included")
      result = session.assessments.create!(
        player_profile_id: player_id, coach_profile: @coach,
        assessment_definition: @definition, created_by: @creator, status: "draft"
      )
      @definition.assessment_categories.ordered.each_with_index do |category, index|
        result.assessment_category_scores.create!(
          assessment_category: category, scale: "one_to_ten", value: values[index]
        )
      end
    end
    session
  end

  def consolidate(*sessions)
    RankingConsolidationBuilder.new(
      assessment_definition: @definition, session_ids: sessions.map(&:id)
    ).call
  end

  def publish!(consolidation)
    travel_to(T_FROZEN) do
      RankingConsolidationPublisher.new(consolidation).call
    end
    consolidation.reload
  end

  # Three fixed instants — the ranking is frozen, a source is retracted, and a curator
  # signs off the correction. They are pinned to the past so the sources (created
  # moments ago) are genuinely published by the time the ranking is frozen, and are
  # far enough apart that no two land in the same timestamp.
  T_FROZEN  = 3.hours.ago
  T_RETRACT = 2.hours.ago
  T_MID     = 90.minutes.ago
  T_SIGNED  = 1.hour.ago

  # Withdraws a session at an explicit instant. The whole feature turns on *when* a
  # withdrawal happened relative to when the snapshot was computed, so the tests pin
  # that ordering with a frozen clock rather than with a relative offset — a
  # "future" withdrawal would sit after the recalculation's own stamp and read as
  # still stale, which is an artefact of the clock, not the behaviour.
  def withdraw_at(session, time)
    session.update!(status: "withdrawn", updated_at: time)
  end

  # Publishes, then runs the recalculation as a curator signing off the next day, so
  # the correction is unambiguously later than the retraction it accounts for.
  #
  # Reloads first: sources are retracted and restored behind the consolidation's back,
  # and a recalculation must read their current state. A real request always loads the
  # ranking afresh, so reloading here keeps the test honest about that instead of
  # quietly relying on a stale in-memory association.
  def recalculate(consolidation, user: @admin)
    travel_to(T_SIGNED) do
      RankingConsolidationRecalculator.new(consolidation.reload, current_user: user).call
    end
  end

  def john_score(consolidation)
    consolidation.rows.find_by(player_profile_id: @john.id)&.average_score
  end

  def snapshot_for(consolidation, session)
    consolidation.consolidation_sessions
                 .find_by(assessment_session_id: session.id).ranking_snapshot
  end

  # Puts a withdrawn session back to published, the way the admin-only session
  # restore does. `T_SIGNED` keeps it later than the freeze it was excluded at.
  def restore_to_published(session)
    travel_to(T_SIGNED) do
      session.update!(status: "published", published_at: T_SIGNED)
    end
  end

  # --- the distinction that drives everything --------------------------------

  test "a source withdrawn after publication is still counted, and says so" do
    first = published_session(name: "January")
    second = published_session(name: "September")
    consolidation = publish!(consolidate(first, second))

    withdraw_at(second, T_RETRACT)

    # The frozen snapshot is untouched: this is the immutability being preserved,
    # not a defect to be papered over. Both players are still ranked from it.
    assert_equal 2, snapshot_for(consolidation, second).size
    assert_predicate consolidation, :recalculable?
    assert_equal [ second ], consolidation.stale_withdrawn_source_sessions
    assert_empty consolidation.excluded_withdrawn_source_sessions
  end

  test "a source withdrawn before publication is already excluded, so there is nothing to do" do
    first = published_session(name: "January")
    second = published_session(name: "Retracted early")
    withdraw_at(second, T_FROZEN - 1.day)

    consolidation = publish!(consolidate(first, second))

    assert_empty consolidation.stale_withdrawn_source_sessions
    assert_equal [ second ], consolidation.excluded_withdrawn_source_sessions
    assert_not_predicate consolidation, :recalculable?
  end

  test "a draft with a withdrawn source reports it as excluded, not stale" do
    # A draft has no frozen snapshot yet, so there is no "after" for a withdrawal to
    # fall into. Reporting it as stale would offer a correction to a draft that
    # re-derives itself at publish anyway.
    first = published_session(name: "January")
    second = published_session(name: "September")
    withdraw_at(second, T_FROZEN - 1.day)

    consolidation = consolidate(first, second)

    assert_empty consolidation.stale_withdrawn_source_sessions
    assert_equal [ second ], consolidation.excluded_withdrawn_source_sessions
    assert_not_predicate consolidation, :recalculable?
  end

  # --- the correction --------------------------------------------------------

  test "recalculating drops a stale source and keeps the rest" do
    first = published_session(name: "January")
    second = published_session(name: "September")
    consolidation = publish!(consolidate(first, second))
    withdraw_at(second, T_RETRACT)

    recalculate(consolidation)
    consolidation.reload

    # The source association survives — a withdrawal is not a removal, and history
    # must still show that September was ever part of this ranking.
    assert_equal 2, consolidation.consolidation_sessions.count
    assert_equal second, consolidation.assessment_sessions.find_by(id: second.id)
    assert_empty snapshot_for(consolidation, second)

    # And the numbers now match January alone.
    assert_equal 80, john_score(consolidation)
    assert_equal 1, consolidation.rows.find_by(player_profile_id: @john.id).coverage
  end

  test "recalculating preserves published_at and records who corrected it" do
    consolidation = publish!(consolidate(published_session(name: "January"),
                                         published_session(name: "September")))
    published_at = consolidation.published_at
    withdraw_at(consolidation.assessment_sessions.last, T_RETRACT)

    recalculate(consolidation, user: @curator)
    consolidation.reload

    # `published_at` answers "when did this become the club's result", which a later
    # correction does not change. The correction carries its own stamp instead.
    assert_equal published_at, consolidation.published_at
    assert_not_nil consolidation.recalculated_at
    assert_operator consolidation.recalculated_at, :>, published_at
    assert_equal @curator, consolidation.recalculated_by
  end

  test "a recalculation is itself a snapshot, so it is not offered twice" do
    consolidation = publish!(consolidate(published_session(name: "January"),
                                         published_session(name: "September")))
    withdraw_at(consolidation.assessment_sessions.last, T_RETRACT)

    recalculate(consolidation)

    # After the correction `computed_at` is later than the withdrawal, so the source
    # reads as excluded rather than stale. The action is spent.
    assert_not_predicate consolidation.reload, :recalculable?
    assert_equal 1, consolidation.excluded_withdrawn_source_sessions.size

    error = assert_raises(RankingConsolidationRecalculator::Error) do
      recalculate(consolidation)
    end
    assert_match(/nothing to recalculate/, error.message)
  end

  test "a source withdrawn before the recalculation is left out of it too" do
    # Guards the ordering assumption: `computed_at` is stamped after the rebuild, so
    # every withdrawal already on record at that moment must come out excluded.
    consolidation = publish!(consolidate(published_session(name: "January"),
                                         published_session(name: "September"),
                                         published_session(name: "November")))
    sources = consolidation.assessment_sessions.to_a
    withdraw_at(sources[1], T_RETRACT)
    withdraw_at(sources[2], T_MID)

    recalculate(consolidation)

    assert_empty consolidation.reload.stale_withdrawn_source_sessions
    assert_equal 2, consolidation.excluded_withdrawn_source_sessions.size
  end

  # --- a source restored to published -----------------------------------------
  #
  # The mirror image of a stale withdrawal. There the snapshot holds scores that
  # should be gone; here the snapshot is *missing* scores that should be present, and
  # without this the ranking silently under-reports while claiming full coverage.

  test "a source restored to published is detected as missing from the ranking" do
    first = published_session(name: "January")
    second = published_session(name: "Retracted, then restored")
    withdraw_at(second, T_FROZEN - 1.hour)
    consolidation = publish!(consolidate(first, second))

    # Excluded while withdrawn, so it is genuinely out of the frozen numbers — and
    # because it was excluded rather than counted, there is nothing to correct yet.
    assert_empty snapshot_for(consolidation, second)
    assert_not_predicate consolidation, :recalculable?

    restore_to_published(second)

    # It scores again, but the ranking has not changed: the snapshot is still empty,
    # so the ranking under-reports and must say so rather than drift silently. The
    # reload mirrors a fresh page load — each API request reads the ranking anew.
    assert_equal 80, john_score(consolidation.reload)
    assert_equal [ second ], consolidation.restored_source_sessions
    assert_predicate consolidation, :recalculable?
    # It is no longer withdrawn, so it belongs to neither withdrawn bucket.
    assert_empty consolidation.stale_withdrawn_source_sessions
    assert_empty consolidation.excluded_withdrawn_source_sessions
  end

  test "recalculating picks a restored source back up" do
    first = published_session(name: "January")                  # John 80
    second = published_session(name: "Retracted, then restored") # John 20
    withdraw_at(second, T_FROZEN - 1.hour)
    consolidation = publish!(consolidate(first, second))

    # Frozen while withdrawn, so it is out of the figures and no correction is due.
    # Coverage of 1 is the visible symptom: the ranking is resting on one session.
    assert_equal 1, consolidation.rows.find_by(player_profile_id: @john.id).coverage
    assert_not_predicate consolidation, :recalculable?

    restore_to_published(second)
    recalculate(consolidation)

    # The restored session's scores are in, so the player is now ranked by both.
    assert_equal 2, snapshot_for(consolidation, second).size
    assert_equal 2, consolidation.rows.find_by(player_profile_id: @john.id).coverage

    # And the correction is spent: nothing is missing and nothing is stale.
    assert_empty consolidation.restored_source_sessions
    assert_empty consolidation.stale_withdrawn_source_sessions
    assert_not_predicate consolidation, :recalculable?
  end

  test "a restored source is not presented as included while the ranking ignores it" do
    first = published_session(name: "January")
    second = published_session(name: "Retracted, then restored")
    withdraw_at(second, T_FROZEN - 1.hour)
    consolidation = publish!(consolidate(first, second))
    restore_to_published(second)

    join = consolidation.reload.consolidation_sessions
                   .find_by(assessment_session_id: second.id)
    # The snapshot row is the authority, and it still says excluded. Reporting `true`
    # here because the session is published again is exactly the bug: the screen
    # would claim a ranking that demonstrably does not contain these scores.
    assert_not join.included_in_ranking?
  end

  # --- refusals --------------------------------------------------------------

  test "a draft is not recalculated, because it re-derives at publish anyway" do
    consolidation = consolidate(published_session(name: "January"))

    error = assert_raises(RankingConsolidationRecalculator::Error) { recalculate(consolidation) }

    assert_match(/only a published ranking/i, error.message)
  end

  test "a withdrawn ranking is restored, not recalculated in place" do
    first = published_session(name: "January")
    second = published_session(name: "September")
    consolidation = publish!(consolidate(first, second))
    withdraw_at(second, T_FROZEN - 1.hour)
    consolidation.update!(status: "withdrawn", published_at: nil)

    error = assert_raises(RankingConsolidationRecalculator::Error) do
      recalculate(consolidation)
    end

    assert_match(/restored/, error.message)
  end

  test "a ranking whose every source was withdrawn is not recalculated into an empty one" do
    first = published_session(name: "January")
    second = published_session(name: "September")
    consolidation = publish!(consolidate(first, second))
    withdraw_at(first, T_RETRACT)
    withdraw_at(second, T_SIGNED)

    error = assert_raises(RankingConsolidationRecalculator::Error) do
      recalculate(consolidation)
    end

    assert_match(/nothing to rank/, error.message)
    # A refused correction changes nothing rather than half-applying: the published
    # ranking is left exactly as it was.
    assert_predicate consolidation.reload, :published?
    assert_equal 2, consolidation.rows.count
  end
end
