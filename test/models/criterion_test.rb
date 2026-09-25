require "test_helper"

# Phase 6 (Assessment Sessions), plan S5: the criteria structure is created ahead
# of its use, so what these tests pin is twofold —
#
#   * the rules a later criteria phase will depend on are already enforced (the
#     per-area uniqueness, the ordering, and the cross-area integrity that stops
#     a score quoting another category's criterion);
#   * creating the structure changed *nothing* about how a category is scored: a
#     category still carries exactly one row, `criterion_id` stays NULL, and the
#     weighted aggregate is untouched.
class CriterionTest < ActiveSupport::TestCase
  setup do
    @coach_user = users(:six)
    @player = player_profiles(:pedro_player)
    @coach = coach_profiles(:maria_coach)
    @definition = assessment_definitions(:balanced)
    @attack = assessment_categories(:balanced_attack)
    @defense = assessment_categories(:balanced_defense)
  end

  # --- the model -------------------------------------------------------------

  test "a criterion names a scored item inside one configured category" do
    row = @attack.criteria.ordered.first

    assert_equal "Approach footwork", row.name
    assert_equal 0, row.position
    assert_equal @attack, row.assessment_category
  end

  test "criteria are ordered by position" do
    assert_equal [ "Approach footwork", "Arm swing" ], @attack.criteria.ordered.map(&:name)
  end

  test "a name is required and is stripped" do
    row = @attack.criteria.build(name: "   ")

    assert_not row.valid?
    assert_includes row.errors.attribute_names, :name

    row.name = "  Transition  "
    assert_equal "Transition", row.name
  end

  test "the same name may not be listed twice under one area, whatever the case" do
    duplicate = @attack.criteria.build(name: "approach FOOTWORK")

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :name
  end

  test "the same name may appear under a different area" do
    row = @defense.criteria.build(name: "Approach footwork")

    assert row.valid?, row.errors.full_messages.inspect
  end

  test "a position may not be negative" do
    row = @attack.criteria.build(name: "Block read", position: -1)

    assert_not row.valid?
    assert_includes row.errors.attribute_names, :position
  end

  test "metadata carries the name and position for serialization" do
    row = criteria(:balanced_attack_approach)

    assert_equal({ id: row.id, name: "Approach footwork", position: 0 }, row.metadata)
  end

  test "criteria follow their category when the configuration is removed" do
    definition = AssessmentDefinition.create!(name: "Throwaway #{SecureRandom.hex(4)}", status: "draft")
    category = definition.assessment_categories.create!(
      category: categories(:assessment_rubric), weight: 100, position: 0
    )
    criterion = category.criteria.create!(name: "Approach", position: 0)

    definition.destroy!

    assert_nil Criterion.find_by(id: criterion.id)
  end

  # --- what creating the structure must NOT have changed ----------------------

  test "a category still carries exactly one score row" do
    assessment = build_result
    assessment.save!
    assessment.assessment_category_scores.create!(assessment_category: @attack, scale: "one_to_ten")

    duplicate = assessment.assessment_category_scores.build(
      assessment_category: @attack, scale: "one_to_ten"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :assessment_category_id
  end

  # The reason the index was split into two partial ones: the rule that matters
  # today has to survive the split, not merely the model validation.
  test "the database still refuses a second score row for the same category" do
    assessment = build_result
    assessment.save!
    assessment.assessment_category_scores.create!(assessment_category: @attack, scale: "one_to_ten")

    duplicate = assessment.assessment_category_scores.new(
      assessment_category: @attack, scale: "one_to_ten"
    )

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "every score row written today leaves criterion_id null" do
    assessment = build_result
    assessment.save!
    assessment.assessment_category_scores.create!(assessment_category: @attack, scale: "one_to_ten")

    assert_nil assessment.assessment_category_scores.last.criterion_id
  end

  # --- the room S5 deliberately left for a later phase -----------------------

  # The partial index on `criterion_id IS NOT NULL` already permits one row per
  # criterion, so a future phase adds rows without another migration here. It has
  # no effect on the aggregate yet — `definition_fully_scored?` still counts one
  # row per category, which is exactly what S5 says.
  test "a score row may name a criterion, and the aggregate ignores it for now" do
    assessment = build_result
    assessment.save!

    assessment.assessment_category_scores.create!(
      assessment_category: @attack, criterion: criteria(:balanced_attack_approach), scale: "one_to_ten"
    )
    assessment.assessment_category_scores.create!(
      assessment_category: @attack, criterion: criteria(:balanced_attack_swing), scale: "one_to_ten"
    )

    assert_equal 2, assessment.assessment_category_scores.reload.size
    assert_nil assessment.reload.score, "scoring does not read criteria yet (S5)"
  end

  test "a score may not quote a criterion from another category" do
    assessment = build_result
    assessment.save!

    row = assessment.assessment_category_scores.build(
      assessment_category: @attack,
      criterion: criteria(:balanced_defense_reading),
      scale: "one_to_ten"
    )

    assert_not row.valid?
    assert_includes row.errors[:criterion].join, "must belong to the category it scores"
  end

  test "the uniqueness rule for criterion rows is scoped to the category" do
    assessment = build_result
    assessment.save!
    criterion = criteria(:balanced_attack_approach)

    assessment.assessment_category_scores.create!(
      assessment_category: @attack, criterion: criterion, scale: "one_to_ten"
    )
    duplicate = assessment.assessment_category_scores.build(
      assessment_category: @attack, criterion: criterion, scale: "one_to_ten"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :criterion_id
  end

  test "a criterion that has been scored is not removed from under its history" do
    assessment = build_result
    assessment.save!
    criterion = criteria(:balanced_attack_approach)
    assessment.assessment_category_scores.create!(
      assessment_category: @attack, criterion: criterion, scale: "one_to_ten"
    )

    assert_not criterion.destroy
    assert_includes criterion.errors.attribute_names, :base
  end

  test "a score's metadata names the criterion it scores" do
    assessment = build_result
    assessment.save!
    row = assessment.assessment_category_scores.create!(
      assessment_category: @attack, criterion: criteria(:balanced_attack_approach), scale: "one_to_ten"
    )

    payload = row.metadata

    assert_equal criteria(:balanced_attack_approach).id, payload[:criterion_id]
    assert_equal "Approach footwork", payload[:criterion][:name]
    assert_equal 40, payload[:weight]
  end

  test "a score without a criterion reports null rather than omitting the keys" do
    assessment = build_result
    assessment.save!
    row = assessment.assessment_category_scores.create!(assessment_category: @attack, scale: "one_to_ten")

    payload = row.metadata

    assert_nil payload[:criterion_id]
    assert_nil payload[:criterion]
  end

  private

  def build_result(status: "draft")
    Assessment.new(
      player_profile: @player,
      coach_profile: @coach,
      created_by: @coach_user,
      assessment_definition: @definition,
      status: status
    )
  end
end
