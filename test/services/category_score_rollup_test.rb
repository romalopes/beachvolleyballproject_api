require "test_helper"

# Reducing a category's score rows to the single number the weighted aggregate
# consumes (plan D16).
#
# The two cases are the whole contract:
#   * a category scored as a whole area (criterion_id NULL) passes through
#     untouched, which is what keeps every historical result valid;
#   * a category scored through its criteria averages them.
#
# The invariant that matters most is the last group: a partially scored
# criterion set contributes nothing rather than a partial mean, because a
# missing score is never a zero (D14).
class CategoryScoreRollupTest < ActiveSupport::TestCase
  Row = Struct.new(:criterion_id, :score) do
    def rated?
      score.present?
    end
  end

  test "a whole-area row is its own rollup, unchanged" do
    result = CategoryScoreRollup.category_level([ Row.new(nil, 80) ])

    assert_equal 80, result.score
    assert_predicate result, :rated?
  end

  test "an unrated whole-area row is not rated rather than rated as zero" do
    result = CategoryScoreRollup.category_level([ Row.new(nil, nil) ])

    assert_nil result.score
    assert_not_predicate result, :rated?
  end

  test "a category with no rows at all contributes nothing" do
    result = CategoryScoreRollup.category_level([])

    assert_nil result.score
    assert_not_predicate result, :rated?
  end

  test "criterion scores average into the category's contribution" do
    criteria = [ Criterion.new(id: 1), Criterion.new(id: 2), Criterion.new(id: 3) ]
    rows = [ Row.new(1, 50), Row.new(2, 60), Row.new(3, 70) ]

    result = CategoryScoreRollup.for(rows, criteria: criteria)

    assert_equal 60, result.score
    assert_equal 3, result.criteria_count
    assert_equal 3, result.rated_count
  end

  test "a single criterion is the identity, matching a whole-area score" do
    criteria = [ Criterion.new(id: 1) ]

    result = CategoryScoreRollup.for([ Row.new(1, 70) ], criteria: criteria)

    assert_equal 70, result.score
  end

  test "the mean rounds half-up to the canonical integer" do
    criteria = [ Criterion.new(id: 1), Criterion.new(id: 2), Criterion.new(id: 3) ]
    rows = [ Row.new(1, 10), Row.new(2, 20), Row.new(3, 31) ]

    # 61/3 = 20.33 -> 20; the point is it never truncates toward a worse claim.
    assert_equal 20, CategoryScoreRollup.for(rows, criteria: criteria).score
  end

  test "a partially rated criterion set contributes nothing, not a partial mean" do
    criteria = [ Criterion.new(id: 1), Criterion.new(id: 2) ]
    rows = [ Row.new(1, 90), Row.new(2, nil) ]

    result = CategoryScoreRollup.for(rows, criteria: criteria)

    assert_nil result.score, "a missing criterion is not a zero"
    assert_not_predicate result, :rated?
    assert_equal 1, result.rated_count
    assert_equal 2, result.criteria_count
  end

  test "a criterion scoring zero is rated, not missing" do
    criteria = [ Criterion.new(id: 1) ]
    result = CategoryScoreRollup.for([ Row.new(1, 0) ], criteria: criteria)

    assert_equal 0, result.score
    assert_predicate result, :rated?
  end

  test "a missing criterion row is incomplete even when the count matches" do
    # Two criteria, two rows, but the rows name the same criterion: the count
    # alone must not be mistaken for completeness.
    criteria = [ Criterion.new(id: 1), Criterion.new(id: 2) ]
    rows = [ Row.new(1, 80), Row.new(1, 80) ]

    assert_nil CategoryScoreRollup.for(rows, criteria: criteria).score
  end

  test "a category with no criteria is never treated as criterion scored" do
    assert_nil CategoryScoreRollup.for([ Row.new(nil, 80) ], criteria: []).score
  end
end
