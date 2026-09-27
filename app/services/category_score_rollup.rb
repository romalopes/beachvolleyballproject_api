# How one configured category's several criterion scores become the single
# number the weighted aggregate consumes.
#
# The whole point of the criteria layer is that a category stops being one
# number: "Attack" might be scored on approach footwork, reception and finish,
# and the area's contribution to the aggregate is a roll-up of those. This
# object owns that roll-up so the three places that need it — the weighted
# total, the publish gate and the ranking's missing-category check — cannot
# drift apart. They all asked the same question and previously each answered
# it from the raw rows.
#
# Two shapes exist, and which one applies is decided by the *category*, never
# by what happens to be in the score rows:
#
#   * no criteria  — the single category-level row (criterion_id NULL) is the
#     area's score, exactly as before. This is every row written today, so
#     normalisation is the identity and no historical result is reinterpreted
#     (D16: nothing existing is assigned a fabricated criterion).
#   * criteria     — every criterion is rated, and the area's score is their
#     unweighted mean, rounded to the canonical integer.
#
# Incomplete is not partial. A half-scored category contributes nothing, exactly
# as a half-scored definition already does: a missing score is never a zero and
# a partial total must never read as a finished one (D14).
module CategoryScoreRollup
  # One category's score, reduced to the number the aggregate needs.
  #
  # `score` is nil when the category is not fully rated; `rated?` distinguishes
  # "not rated" from "rated as zero", which are very different claims about a
  # player.
  Result = Struct.new(:score, :criteria_count, :rated_count, keyword_init: true) do
    def rated?
      score.present?
    end

    def complete?
      criteria_count.positive? && rated_count == criteria_count
    end
  end

  class << self
    # The rows belong to a single category. They may be loaded or built.
    def for(rows, criteria:)
      return Result.new(score: nil, criteria_count: 0, rated_count: 0) if criteria.empty?

      scored = rows.select { |row| row.criterion_id.present? }
      # A criterion-level rollup never consumes a category-level row, and a
      # category without criteria never consumes a criterion row. Mixing them
      # would let a half-migrated category average two different grains.
      expected = criteria.map(&:id)
      return incomplete(expected) unless scored.size == expected.size
      return incomplete(expected) unless scored.map(&:criterion_id).sort == expected.sort

      values = scored.filter_map(&:score)
      return incomplete(expected, values.size) unless values.size == expected.size

      # Unweighted mean, rounded to the canonical integer like the weighted
      # total. Rounding half-up keeps 3 criteria at 50/60/70 landing on 60.
      Result.new(
        score: (values.sum.to_f / values.size).round,
        criteria_count: expected.size,
        rated_count: values.size
      )
    end

    # Never a partial number: an unrated criterion leaves the category
    # contributing nothing, with the counts kept so a caller can say which.
    def incomplete(expected_ids, rated = 0)
      Result.new(score: nil, criteria_count: expected_ids.size, rated_count: rated)
    end

    # The identity case: a category with no criteria carries its own score on
    # the single category-level row. Kept here so callers never branch on
    # `criterion_id.nil?` themselves.
    def category_level(rows)
      row = rows.find { |candidate| candidate.criterion_id.nil? }
      return Result.new(score: nil, criteria_count: 0, rated_count: 0) if row.nil? || !row.rated?

      Result.new(score: row.score, criteria_count: 0, rated_count: 0)
    end
  end
end
