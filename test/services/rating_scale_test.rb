require "test_helper"

# The rating scale is the single place where a coach's number becomes the
# canonical 0..100 the club compares against, so it is pinned row by row. This
# matrix is the contract; docs/ASSESSMENT_INTEGRATION_PLAN.md and the SPA's
# src/utils/rating.test.ts assert the same table.
class RatingScaleTest < ActiveSupport::TestCase
  SCORES = [ 0, 9, 10, 19, 20, 29, 30, 39, 40, 49, 50, 59, 60, 69, 70, 79, 80, 89, 90, 99, 100 ].freeze
  TEN_SCALE = [ 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10 ].freeze
  FIVE_SCALE = [ 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 5 ].freeze

  test "canonical scores map to both display scales" do
    assert_equal SCORES.length, TEN_SCALE.length
    assert_equal SCORES.length, FIVE_SCALE.length

    SCORES.zip(TEN_SCALE, FIVE_SCALE).each do |score, ten, five|
      assert_equal ten, RatingScale.to_ten(score), "to_ten(#{score})"
      assert_equal five, RatingScale.to_five(score), "to_five(#{score})"
    end
  end

  test "the 1-10 scale round-trips" do
    (1..10).each do |value|
      score = RatingScale.to_score(value, scale: "one_to_ten")

      assert_equal value * 10, score
      assert_equal value, RatingScale.to_ten(score), "round-trip for #{value}/10"
    end
  end

  test "the 1-5 scale round-trips through its band midpoints" do
    { 1 => 10, 2 => 30, 3 => 50, 4 => 70, 5 => 90 }.each do |value, score|
      assert_equal score, RatingScale.to_score(value, scale: "one_to_five")
      assert_equal value, RatingScale.to_five(score), "round-trip for #{value}/5"
    end
  end

  test "both display scales agree with each other" do
    # 70 is a 7 out of 10 and a 4 out of 5 at the same time: only the entry
    # grids differ, never the reading of a stored score.
    assert_equal 7, RatingScale.to_ten(70)
    assert_equal 4, RatingScale.to_five(70)
    assert_equal 1, RatingScale.to_five(10)
    assert_equal 10, RatingScale.to_ten(100)
    assert_equal 5, RatingScale.to_five(90)
  end

  test "display scales never decrease as the score rises" do
    (0..100).each_cons(2) do |lower, higher|
      assert_operator RatingScale.to_ten(higher), :>=, RatingScale.to_ten(lower)
      assert_operator RatingScale.to_five(higher), :>=, RatingScale.to_five(lower)
    end
  end

  test "an unrated row has no display value and says so" do
    assert_nil RatingScale.to_ten(nil)
    assert_nil RatingScale.to_five(nil)
    assert_equal "Not rated yet", RatingScale.describe(nil)
  end

  test "describe names every scale at once" do
    assert_equal "70/100 · 7/10 · 4/5", RatingScale.describe(70)
    assert_equal "100/100 · 10/10 · 5/5", RatingScale.describe(100)
    assert_equal "0/100 · 0/10 · 1/5", RatingScale.describe(0)
  end

  test "legal_value? answers for the scale it is asked about" do
    assert RatingScale.legal_value?(5, scale: "one_to_five")
    assert_not RatingScale.legal_value?(6, scale: "one_to_five")
    assert RatingScale.legal_value?(10, scale: "one_to_ten")
    assert_not RatingScale.legal_value?(11, scale: "one_to_ten")
    assert_not RatingScale.legal_value?(4, scale: "one_to_hundred")
    assert_not RatingScale.legal_value?(nil, scale: "one_to_five")
  end

  test "to_score reads the numeric strings a JSON body arrives with" do
    assert_equal 70, RatingScale.to_score("4", scale: "one_to_five")
    assert_equal 40, RatingScale.to_score("4", scale: "one_to_ten")
  end

  test "to_score rejects rather than clamping" do
    assert_raises(ArgumentError) { RatingScale.to_score(11, scale: "one_to_ten") }
    assert_raises(ArgumentError) { RatingScale.to_score(0, scale: "one_to_five") }
    assert_raises(ArgumentError) { RatingScale.to_score(-1, scale: "one_to_ten") }
    assert_raises(ArgumentError) { RatingScale.to_score(nil, scale: "one_to_five") }
    assert_raises(ArgumentError) { RatingScale.to_score(4, scale: "one_to_hundred") }
  end
end
