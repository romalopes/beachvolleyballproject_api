require "test_helper"

# The rules an assessment carries, and the two predicates the API is built on:
# `visible_to` ("does this row exist for you?") and `manageable_by?` ("may you
# change it?"). Both are model-level so a controller can never re-implement them.
class AssessmentTest < ActiveSupport::TestCase
  setup do
    @coach_user = users(:six)      # coach, and the only fixture user with a coach profile
    @other_coach = users(:three)   # coach role, owns nothing, no coach profile
    @admin = users(:two)
    @curator = users(:four)
    @player_user = users(:one)     # player role only

    @player = player_profiles(:pedro_player)
    @coach = coach_profiles(:maria_coach)
  end

  test "a published skill-based assessment is valid" do
    assert assessments(:skill_active).valid?
  end

  test "a withdrawn assessment is valid" do
    assessment = assessments(:custom_withdrawn)

    assert assessment.valid?
    assert assessment.withdrawn?
    assert_not assessment.publicly_visible?
  end

  test "an unrated draft is valid" do
    draft = assessments(:draft_assigned)

    assert draft.draft?
    assert_nil draft.score
    assert_nil draft.ten_scale
    assert_nil draft.five_scale
    assert draft.valid?
  end

  test "an unrated row cannot leave draft" do
    draft = assessments(:draft_assigned)
    draft.status = "active"

    assert_not draft.valid?
    assert_includes draft.errors.attribute_names, :score
  end

  test "a rated draft may be published" do
    draft = assessments(:draft_ready)
    draft.status = "active"

    assert draft.valid?
    assert draft.active?
  end

  test "the score stays inside 0..100" do
    assessment = build_assessment(score: 101, reported_value: 11, scale: "one_to_ten")
    assert_not assessment.valid?
    assert_includes assessment.errors.attribute_names, :score

    assert_not build_assessment(score: -1, reported_value: 1, scale: "one_to_ten").valid?
    assert_not build_assessment(score: 70.5, reported_value: 7, scale: "one_to_ten").valid?
  end

  test "the reported value must exist on the scale it was given on" do
    assessment = build_assessment(score: 90, reported_value: 6, scale: "one_to_five")

    assert_not assessment.valid?
    assert_includes assessment.errors.attribute_names, :reported_value
    assert_includes assessment.errors[:reported_value].join, "one_to_five"
  end

  test "the canonical score must follow from the reported value" do
    assessment = build_assessment(score: 60, reported_value: 4, scale: "one_to_five")

    assert_not assessment.valid?
    assert_includes assessment.errors[:score].join, "does not match"
  end

  test "the score and the reported value travel together" do
    without_reported = build_assessment(score: 70, reported_value: nil)
    assert_not without_reported.valid?
    assert_includes without_reported.errors.attribute_names, :reported_value

    without_score = build_assessment(status: "draft", score: nil, reported_value: 4)
    assert_not without_score.valid?
    assert_includes without_score.errors.attribute_names, :score
  end

  test "the rubric is a skill or free text, never both and never neither" do
    both = build_assessment(skill: skills(:assessment_rubric), custom_skill: "Court communication")
    assert_not both.valid?
    assert_includes both.errors.attribute_names, :custom_skill

    neither = build_assessment(skill: nil, custom_skill: nil)
    assert_not neither.valid?
    assert_includes neither.errors.attribute_names, :base
  end

  test "a person may not assess their own player profile" do
    # One Person, both profiles: exactly the case the validation exists for.
    own_coach_profile = CoachProfile.create!(person: people(:one), status: "active")
    assessment = Assessment.new(
      player_profile: player_profiles(:john_player),
      coach_profile: own_coach_profile,
      created_by: @coach_user,
      skill: skills(:assessment_rubric),
      score: 70,
      reported_value: 4,
      scale: "one_to_five",
      status: "active"
    )

    assert_not assessment.valid?
    assert_includes assessment.errors.attribute_names, :coach_profile
    assert_includes assessment.errors[:coach_profile].join, "cannot be the same person"
  end

  test "another coach may assess a person who is both player and coach" do
    person = people(:one)
    person.create_coach_profile!(status: "active")

    assessment = Assessment.new(
      player_profile: player_profiles(:john_player),
      coach_profile: @coach,
      created_by: @coach_user,
      skill: skills(:assessment_rubric),
      score: 70,
      reported_value: 4,
      scale: "one_to_five",
      status: "active"
    )

    assert assessment.valid?
  end

  test "a profile that recorded assessments is never destroyed" do
    assert_not @coach.destroy
    assert @coach.persisted?
    assert Assessment.exists?(assessments(:skill_active).id)
  end

  # --- existence: visible_to -------------------------------------------------

  test "oversight sees every row, in every status" do
    [ @admin, @curator ].each do |overseer|
      visible = Assessment.visible_to(overseer)

      assert_includes visible, assessments(:skill_active)
      assert_includes visible, assessments(:draft_ready)
      assert_includes visible, assessments(:draft_assigned)
      assert_includes visible, assessments(:custom_withdrawn)
    end
  end

  test "the recorder and the attributed coach see their own rows in any status" do
    visible = Assessment.visible_to(@coach_user)

    assert_includes visible, assessments(:skill_active)
    assert_includes visible, assessments(:draft_ready)
    assert_includes visible, assessments(:draft_assigned)
    assert_includes visible, assessments(:custom_withdrawn)
  end

  test "another coach sees only published rows" do
    visible = Assessment.visible_to(@other_coach)

    assert_includes visible, assessments(:skill_active)
    assert_not_includes visible, assessments(:draft_ready)
    assert_not_includes visible, assessments(:draft_assigned)
    assert_not_includes visible, assessments(:custom_withdrawn)
  end

  test "a private player hides their published assessments from other coaches" do
    @player.update!(visibility: "private", created_by: @admin)

    assert_not_includes Assessment.visible_to(@other_coach), assessments(:skill_active)
    # …but the coach who recorded it keeps sight of their own row: being a
    # stakeholder beats the player's visibility.
    assert_includes Assessment.visible_to(@coach_user), assessments(:skill_active)
    assert_includes Assessment.visible_to(@admin), assessments(:skill_active)
  end

  test "oversight is curators and admins, never coaches" do
    # The one place assessments deliberately differ from the shared schedule:
    # User#content_manager? counts coaches, which would let any coach read and
    # edit any assessment. A rating is one named coach's claim about a player,
    # so a coach reaches only their own rows and curators/admins oversee all.
    assert Assessment.oversight?(@admin)
    assert Assessment.oversight?(@curator)
    assert_not Assessment.oversight?(@coach_user)
    assert_not Assessment.oversight?(@other_coach)
    assert_not Assessment.oversight?(@player_user)
    assert_not Assessment.oversight?(nil)
  end

  test "a user with no relationship to a row sees only published rows" do
    # A player-role user is not a manager, so this is the model staying honest
    # rather than a reachable surface: no relationship, so only published rows
    # on a shared player.
    assert_includes Assessment.visible_to(@player_user), assessments(:skill_active)
    assert_not_includes Assessment.visible_to(@player_user), assessments(:draft_ready)
    assert_not_includes Assessment.visible_to(@player_user), assessments(:custom_withdrawn)
  end

  test "visible_to_user? answers for a single row" do
    assert assessments(:skill_active).visible_to_user?(@other_coach)
    assert assessments(:skill_active).publicly_visible?

    assert_not assessments(:custom_withdrawn).visible_to_user?(@other_coach)
    assert assessments(:custom_withdrawn).visible_to_user?(@coach_user)

    assert_not assessments(:draft_ready).visible_to_user?(@other_coach)
    assert assessments(:draft_ready).visible_to_user?(@coach_user)

    # nil is the anonymous/public view — the same case PlayerProfile answers true
    # for on a shared profile (phase 3.C). The API authenticates before it asks,
    # so what matters here is that an unfinished or retracted row is never part
    # of that public view.
    assert assessments(:skill_active).visible_to_user?(nil)
    assert_not assessments(:draft_ready).visible_to_user?(nil)
    assert_not assessments(:custom_withdrawn).visible_to_user?(nil)

    assert_includes Assessment.visible_to(nil), assessments(:skill_active)
    assert_not_includes Assessment.visible_to(nil), assessments(:draft_ready)
    assert_not_includes Assessment.visible_to(nil), assessments(:custom_withdrawn)
  end

  # --- authority -------------------------------------------------------------

  test "the recorder, the attributed coach and oversight may change a row" do
    row = assessments(:skill_active)

    assert row.manageable_by?(@coach_user)
    assert row.manageable_by?(@admin)
    assert row.manageable_by?(@curator)
    assert_not row.manageable_by?(@other_coach)
    assert_not row.manageable_by?(@player_user)
    assert_not row.manageable_by?(nil)
  end

  test "stakeholder? recognises exactly the two relationships" do
    assert assessments(:skill_active).stakeholder?(@coach_user)
    assert_not assessments(:skill_active).stakeholder?(@other_coach)
    assert_not assessments(:skill_active).stakeholder?(nil)
  end

  test "a row attributed to a coach without an account is managed by its recorder and oversight" do
    # A second accountless Person: the attributed coach must be somebody other
    # than the assessed player, or the self-assessment rule would refuse the row.
    accountless_coach = Person.create!(
      first_name: "Accountless",
      last_name: "Coach",
      creation_source: "coach_created",
      created_by: @other_coach
    ).create_coach_profile!(status: "active")

    row = build_assessment(coach_profile: accountless_coach, created_by: @other_coach)
    row.save!

    assert_nil row.coach_account_user_id
    assert row.stakeholder?(@other_coach), "the recorder keeps managing it"
    assert row.manageable_by?(@admin), "oversight always may"
    assert_not row.manageable_by?(@coach_user)
  end

  # --- derived values --------------------------------------------------------

  test "display helpers follow the stored pair" do
    row = assessments(:skill_active)

    assert_equal 70, row.score
    assert_equal 4, row.reported_value
    assert_equal "one_to_five", row.scale
    assert_equal 7, row.ten_scale
    assert_equal 4, row.five_scale
    assert_equal "70/100 · 7/10 · 4/5", row.score_label
    assert_equal "Active", row.status_label
  end

  test "the rubric is exposed whichever branch it sits on" do
    assert_equal skills(:assessment_rubric).title, assessments(:skill_active).skill_label
    assert_equal "Court communication", assessments(:custom_withdrawn).skill_label
    assert_equal "skill:#{skills(:assessment_rubric).id}", assessments(:skill_active).skill_key
    assert_equal "custom:court communication", assessments(:custom_withdrawn).skill_key
  end

  test "metadata carries the row for a nested payload" do
    payload = assessments(:skill_active).metadata

    assert_equal assessments(:skill_active).id, payload[:id]
    assert_equal 70, payload[:score]
    assert_equal 4, payload[:reported_value]
    assert_equal 7, payload[:ten_scale]
    assert_equal 4, payload[:five_scale]
    assert_equal({ id: @coach_user.id, name: @coach_user.name }, payload[:created_by])
    assert_equal(
      { id: skills(:assessment_rubric).id, title: skills(:assessment_rubric).title, slug: skills(:assessment_rubric).slug },
      payload[:skill]
    )
    assert_equal "Active", payload[:status_label]

    unrated = assessments(:draft_assigned).metadata
    assert_nil unrated[:score]
    assert_nil unrated[:ten_scale]
    assert_nil unrated[:five_scale]
  end

  test "latest_per_skill keeps one row per rubric, newest first" do
    person = Person.create!(first_name: "Grouping", last_name: "Case", creation_source: "system")
    profile = person.create_player_profile!

    older = build_assessment(player_profile: profile, skill: skills(:assessment_rubric))
    older.save!
    older.update_column(:created_at, 3.days.ago)

    newer = build_assessment(player_profile: profile, skill: skills(:assessment_rubric))
    newer.save!
    newer.update_column(:created_at, 1.hour.ago)

    custom = build_assessment(player_profile: profile, skill: nil, custom_skill: "Net play")
    custom.save!

    latest = Assessment.latest_per_skill(profile.assessments)
    keys = latest.map(&:skill_key)

    assert_equal keys.uniq.length, keys.length, "one row per rubric"
    assert_equal 2, keys.length, "skill two (newest wins) and one custom rubric"
    assert_includes latest, newer
    assert_not_includes latest, older
    assert_includes latest, custom
  end

  # --- referential integrity -------------------------------------------------

  test "a rubric in use cannot be hard-deleted" do
    # The XOR constraint requires a rubric, so the database refuses the delete
    # rather than nulling the column — an assessment without a rubric would be
    # meaningless, and losing the skill would silently rewrite history. An
    # in-use skill is therefore retired by editing it, not by deleting it.
    assert_raises(ActiveRecord::InvalidForeignKey) do
      skills(:assessment_rubric).destroy
    end

    assert Assessment.exists?(assessments(:skill_active).id)
  end

  test "deleting the session keeps the assessment and drops only the pointer" do
    # A session is a pointer, not a claim: the rating survives the schedule entry
    # (this is what `on_delete: :nullify` on the column buys us).
    row = assessments(:skill_active)
    assert row.training_session_id.present?

    training_sessions(:one).destroy

    assert Assessment.exists?(row.id), "the assessment outlives the session"
    assert_nil row.reload.training_session_id
    assert_equal 70, row.score, "and it still means what it meant"
  end

  private

  def build_assessment(**attributes)
    Assessment.new({
      player_profile: @player,
      coach_profile: @coach,
      created_by: @coach_user,
      skill: skills(:assessment_rubric),
      score: 70,
      reported_value: 4,
      scale: "one_to_five",
      status: "active"
    }.merge(attributes))
  end
end
