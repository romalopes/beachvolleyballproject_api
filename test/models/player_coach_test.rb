require "test_helper"

# Model rules for the coaching relationship.
#
# Three things are under test, and each is a rule the plan states explicitly:
#   * a period is dates, not a status flag — so `end_date IS NULL` *is* "current";
#   * history is kept — an ended period is never deleted, and a resumed
#     relationship is a new row rather than a reopened one;
#   * a relationship is not an assessment permission — a coach may assess a player
#     with no row here at all.
class PlayerCoachTest < ActiveSupport::TestCase
  setup do
    @john = player_profiles(:john_player)
    @pedro = player_profiles(:pedro_player)
    @maria = coach_profiles(:maria_coach)
    @coach_user = users(:six) # the account behind maria_coach
  end

  # Pedro + Maria has no *open* period in the fixtures (only the ended
  # `historical` one), so it is the pair the tests below are free to open.
  def relationship(overrides = {})
    PlayerCoach.create!(
      { player_profile: @pedro, coach_profile: @maria, start_date: Date.new(2025, 12, 1) }
        .merge(overrides)
    )
  end

  # Unsaved, for the rules that are about validation: `create!` would raise before
  # the assertion could be made.
  def built(overrides = {})
    PlayerCoach.new(
      { player_profile: @pedro, coach_profile: @maria, start_date: Date.new(2025, 12, 1) }
        .merge(overrides)
    )
  end

  def new_player_profile(first_name)
    Person.create!(first_name: first_name, creation_source: "system").create_player_profile!
  end

  def new_coach_profile(first_name)
    Person.create!(first_name: first_name, creation_source: "system").create_coach_profile!
  end

  # --- the period is the lifecycle ------------------------------------------

  test "an open period is current and an ended period is historical" do
    open = player_coaches(:current)
    ended = player_coaches(:historical)

    assert_predicate open, :current?
    assert_not open.ended?
    assert_predicate ended, :ended?
    assert_not ended.current?
  end

  test "current and historical partition the table, and there is no status column" do
    # `end_date` is the only thing that decides, so the two scopes must between
    # them hold every row — a `status` field could drift out of step with it.
    assert_equal PlayerCoach.count, PlayerCoach.current.count + PlayerCoach.historical.count
    assert_equal player_coaches(:current).id, PlayerCoach.current_period_for(@john, @maria).id
    assert_nil PlayerCoach.current_period_for(@pedro, @maria),
               "the only Pedro/Maria period in the fixtures has ended"
  end

  test "a period is inclusive of both of its dates" do
    ended = player_coaches(:historical) # 2025-02-01 .. 2025-11-30

    assert ended.active_on?(ended.start_date)
    assert ended.active_on?(ended.end_date)
    assert_not ended.active_on?(ended.end_date + 1)
    assert_not ended.active_on?(ended.start_date - 1)
    assert_not ended.active_on?(nil)
  end

  test "duration is nil while the relationship is open" do
    # A growing figure must not be readable as a final one.
    assert_nil player_coaches(:current).duration_in_days
    assert_predicate player_coaches(:historical).duration_in_days, :positive?
  end

  test "ending writes the end date and keeps the row" do
    open = player_coaches(:current)

    open.end!(Date.new(2026, 1, 31))

    assert_predicate open.reload, :ended?
    assert_equal Date.new(2026, 1, 31), open.end_date
    assert PlayerCoach.exists?(open.id), "ending a relationship must never remove it"
  end

  # --- a coach can coach many players, a player can have many coaches --------

  test "a coach can coach several players at once" do
    other = new_player_profile("Third")
    relationship(player_profile: other, start_date: Date.new(2025, 12, 1))
    relationship(player_profile: @pedro, start_date: Date.new(2026, 1, 1))

    open_players = @maria.player_coaches.current.pluck(:player_profile_id)

    assert_includes open_players, other.id
    assert_includes open_players, @pedro.id
  end

  test "a player can have several coaches at once" do
    relationship(player_profile: @pedro, coach_profile: @maria, start_date: Date.new(2025, 12, 1))
    relationship(player_profile: @pedro, coach_profile: new_coach_profile("Second"), start_date: Date.new(2026, 1, 1))

    assert_equal 2, @pedro.player_coaches.current.count
    # `distinct`, because the through association joins the periods: Pedro has an
    # earlier Maria stint on the record as well.
    assert_equal 2, @pedro.coaches.distinct.count
  end

  # --- one open period per pair, and no overlapping periods -----------------

  test "a pair cannot have two open periods at once" do
    duplicate = built(player_profile: @john, coach_profile: @maria,
                      start_date: Date.new(2026, 2, 1))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:player_profile],
                    "already has an open coaching relationship with this coach"
  end

  test "the database refuses a second open period for the same pair" do
    # Bypasses the model on purpose: the partial unique index is the guard that
    # survives a race, and this is what pins it. `insert_all!` rather than
    # `insert_all` because the latter adds `ON CONFLICT DO NOTHING` and would
    # report success for a row the database actually refused.
    assert_raises(ActiveRecord::StatementInvalid) do
      PlayerCoach.insert_all!([ {
        player_profile_id: @john.id,
        coach_profile_id: @maria.id,
        start_date: Date.new(2026, 2, 1),
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "a relationship that resumes is a new period, not the old one reopened" do
    earlier = player_coaches(:resumed_earlier)
    current = PlayerCoach.current_period_for(@john, @maria)

    assert_predicate earlier, :ended?
    assert_not_equal earlier.id, current.id
    assert_operator current.start_date, :>, earlier.end_date
    assert_equal 2, @john.player_coaches.count
  end

  test "an ended relationship cannot be reopened by clearing its end date" do
    ended = player_coaches(:historical)

    assert_not ended.update(end_date: nil)
    assert_includes ended.errors[:end_date],
                    "cannot be cleared; a resumed relationship is a new period"
    assert_predicate ended.reload, :ended?
  end

  test "overlapping periods for the same pair are refused" do
    # John and Maria already have a 2025-09-01 open period, so this straddles it.
    overlap = built(player_profile: @john, coach_profile: @maria,
                    start_date: Date.new(2025, 6, 1), end_date: Date.new(2025, 12, 31))

    assert_not overlap.valid?
    assert_includes overlap.errors[:start_date],
                    "overlaps another coaching period for this player and coach"
  end

  test "an end date cannot precede the start date" do
    backwards = built(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 2, 1))

    assert_not backwards.valid?
    assert_includes backwards.errors[:end_date], "cannot be before the start date"
  end

  test "the database refuses an end date before the start date" do
    assert_raises(ActiveRecord::StatementInvalid) do
      PlayerCoach.insert_all!([ {
        player_profile_id: @pedro.id,
        coach_profile_id: @maria.id,
        start_date: Date.new(2026, 3, 1),
        end_date: Date.new(2026, 2, 1),
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end
  end

  test "a person cannot coach themselves" do
    # A Person may hold both profiles; the join still has to name two people.
    person = Person.create!(first_name: "Dual", last_name: "Role", creation_source: "system")
    self_coached = built(player_profile: person.create_player_profile!,
                         coach_profile: person.create_coach_profile!)

    assert_not self_coached.valid?
    assert_includes self_coached.errors[:coach_profile],
                    "cannot be the same person as the player"
  end

  # --- a relationship is not an assessment permission -----------------------

  test "a coach may assess a player with no coaching relationship on record" do
    # The rule the plan states in as many words. Authority to record a rating is
    # settled by the assessment rules, so an empty relationship table must not
    # stand in the way of a rating.
    stranger = new_player_profile("Unrelated")

    assert_nil PlayerCoach.current_period_for(stranger, @maria)
    assert_empty PlayerCoach.for_player(stranger.id)

    assessment = Assessment.new(
      player_profile: stranger,
      coach_profile: @maria,
      created_by: @coach_user,
      category: categories(:assessment_rubric),
      score: 70,
      reported_value: 4,
      scale: "one_to_five",
      status: "active"
    )

    assert_predicate assessment, :valid?, assessment.errors.full_messages.to_sentence
  end

  test "ending a relationship does not disturb the assessments recorded during it" do
    # Pedro's Maria stint is on the record and she assessed him; ending the
    # relationship retracts nothing.
    ended = player_coaches(:historical)
    assessment = assessments(:skill_active)

    assert_equal @pedro.id, assessment.player_profile_id
    assert_equal ended.coach_profile_id, assessment.coach_profile_id

    ended.end!(ended.end_date + 1)

    assert_predicate assessment.reload, :active?
    assert_equal 70, assessment.score
  end

  # --- history is not destroyed --------------------------------------------

  test "a profile with coaching history cannot be destroyed" do
    assert_not @maria.destroy
    assert PlayerCoach.exists?(player_coaches(:current).id)
    assert CoachProfile.exists?(@maria.id)
  end

  test "metadata derives currentness from the end date, never from a stored flag" do
    open = player_coaches(:current).metadata
    ended = player_coaches(:historical).metadata

    assert_equal true, open[:current]
    assert_nil open[:end_date]
    assert_equal "John Smith", open[:player_name]
    assert_equal "Maria Silva", open[:coach_name]

    assert_equal false, ended[:current]
    assert_equal Date.new(2025, 11, 30), ended[:end_date]
  end
end
