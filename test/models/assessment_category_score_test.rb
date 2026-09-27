require "test_helper"

# What the coach scored for one configured category — and the rule that the
# parent's aggregate is never stale or, worse, partial.
class AssessmentCategoryScoreTest < ActiveSupport::TestCase
  setup do
    @coach_user = users(:six)
    @player = player_profiles(:pedro_player)
    @coach = coach_profiles(:maria_coach)
    @definition = assessment_definitions(:balanced)
    @assessment = build_result
  end

  test "the typed entry converts through the band table, per category" do
    row = @assessment.assessment_category_scores.build(
      assessment_category: assessment_categories(:balanced_attack),
      scale: "one_to_five"
    )
    row.value = 4

    assert_equal 4, row.reported_value
    assert_equal 70, row.score
    assert_equal 7, row.ten_scale
    assert_equal 4, row.five_scale
    assert_predicate row, :rated?
  end

  test "an unrated row is not rated and shows as such" do
    row = @assessment.assessment_category_scores.build(
      assessment_category: assessment_categories(:balanced_attack)
    )

    assert_not_predicate row, :rated?
    assert_nil row.ten_scale
    assert_nil row.five_scale
    assert_equal "Not rated yet", row.score_label
  end

  test "an entry outside the scale is not silently accepted" do
    row = @assessment.assessment_category_scores.build(
      assessment_category: assessment_categories(:balanced_attack),
      scale: "one_to_five"
    )
    row.value = 99 # not a legal 1-5 value, so value= leaves the row unrated

    assert_nil row.reported_value
    assert_nil row.score
  end

  test "the canonical score must follow from the reported value" do
    row = @assessment.assessment_category_scores.build(
      assessment_category: assessment_categories(:balanced_attack),
      score: 60,
      reported_value: 4,
      scale: "one_to_five"
    )

    assert_not row.valid?
    assert_includes row.errors[:score].join, "does not match"
  end

  test "the score and the reported value travel together" do
    row = @assessment.assessment_category_scores.build(
      assessment_category: assessment_categories(:balanced_attack),
      score: 70,
      reported_value: nil,
      scale: "one_to_five"
    )

    assert_raises(ActiveRecord::StatementInvalid) { row.save(validate: false) }
  end

  test "saving a score recomputes the parent aggregate" do
    @assessment.save!

    score_into(@assessment, categories_assessment_categories, [ 8, 7, 9 ])

    assert_equal 80, @assessment.reload.score
  end

  test "a partially scored set computes to nil, never to a partial total" do
    @assessment.save!
    attack = categories_assessment_categories.first

    child = @assessment.assessment_category_scores.create!(
      assessment_category: attack, scale: "one_to_ten"
    )
    child.update!(reported_value: 8, score: 80)

    assert_nil @assessment.reload.score, "one of three categories is not a result"
  end

  test "removing a score clears the aggregate rather than leaving a stale one" do
    @assessment.save!
    score_into(@assessment, categories_assessment_categories, [ 8, 7, 9 ])
    assert_equal 80, @assessment.reload.score

    @assessment.assessment_category_scores.first.destroy

    assert_nil @assessment.reload.score
  end

  test "a category scored through its criteria rolls up into the aggregate" do
    @assessment.save!
    # balanced_attack carries two criteria (weight 40). The other categories are
    # scored as whole areas, which is the shape every existing result uses.
    attack = assessment_categories(:balanced_attack)
    others = categories_assessment_categories - [ attack ]

    @assessment.assessment_category_scores.create!(
      assessment_category: attack, criterion: criteria(:balanced_attack_approach),
      scale: "one_to_ten", reported_value: 6, score: 60
    )
    @assessment.assessment_category_scores.create!(
      assessment_category: attack, criterion: criteria(:balanced_attack_swing),
      scale: "one_to_ten", reported_value: 8, score: 80
    )
    others.each do |category|
      row = @assessment.assessment_category_scores.build(assessment_category: category)
      row.scale = "one_to_ten"
      row.value = 8
      row.save!
    end

    # Attack contributes its criterion mean of 70, not 60 and not 140.
    assert_predicate @assessment.reload, :definition_fully_scored?
    expected = (70 * attack.weight + 80 * others.sum(&:weight)) / 100.0
    assert_equal expected.round, @assessment.score
  end

  test "one unrated criterion leaves the whole assessment incomplete" do
    @assessment.save!
    attack = assessment_categories(:balanced_attack)
    others = categories_assessment_categories - [ attack ]

    @assessment.assessment_category_scores.create!(
      assessment_category: attack, criterion: criteria(:balanced_attack_approach),
      scale: "one_to_ten", reported_value: 6, score: 60
    )
    others.each do |category|
      row = @assessment.assessment_category_scores.build(assessment_category: category)
      row.scale = "one_to_ten"
      row.value = 8
      row.save!
    end

    # The second criterion was never rated, so no total — not a mean of one.
    assert_not_predicate @assessment.reload, :definition_fully_scored?
    assert_nil @assessment.score
  end

  test "configuring criteria does not invalidate a whole-area score" do
    @assessment.save!
    # balanced_attack already has two criteria in the fixtures, yet a coach may
    # still score the area as a whole. If the presence of criteria implied
    # criterion scoring, this existing shape would silently stop counting.
    score_into(@assessment, categories_assessment_categories, [ 8, 7, 9 ])

    assert_predicate @assessment.reload, :definition_fully_scored?
    assert_equal 80, @assessment.score
  end

  test "the same category may not be scored twice for one assessment" do
    @assessment.save!
    first = categories_assessment_categories.first

    @assessment.assessment_category_scores.create!(assessment_category: first, scale: "one_to_ten")
    duplicate = @assessment.assessment_category_scores.new(assessment_category: first, scale: "one_to_ten")

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :assessment_category_id
  end

  test "metadata carries the weight beside the score so the SPA can show both" do
    @assessment.save!
    score_into(@assessment, categories_assessment_categories, [ 8, 7, 9 ])

    payload = @assessment.assessment_category_scores.reload.first.metadata

    assert_equal 40, payload[:weight]
    assert_equal 80, payload[:score]
    assert_equal "Attack", payload[:label]
    assert_equal "category", payload[:source_type]
    assert payload[:score_label].include?("80/100")
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

  def categories_assessment_categories
    @definition.assessment_categories.ordered.to_a
  end

  # Score every configured category, in order, on the 1-10 scale.
  def score_into(assessment, rows, values)
    rows.each_with_index do |category_row, index|
      child = assessment.assessment_category_scores.find_or_initialize_by(
        assessment_category: category_row
      )
      child.scale = "one_to_ten"
      child.value = values[index]
      child.save!
    end
  end
end
