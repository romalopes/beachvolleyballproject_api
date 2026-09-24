# Canonical rating scale for coach assessments.
#
# A coach records what they mean ("4 out of 5", "7 out of 10"); the system needs
# one comparable number, so it stores a canonical 0..100 score and keeps the
# coach's own input beside it (Assessment#reported_value / #scale). Keeping the
# typed value is what makes re-tuning these bands a data migration instead of a
# guess.
#
# Entry and display are deliberately different shapes:
#   * entry   — a coarse choice maps to one representative canonical value;
#   * display — a canonical value maps back to the band it falls in.
# Both directions round-trip exactly for every legal input; the matrix that pins
# this lives in docs/ASSESSMENT_INTEGRATION_PLAN.md and in
# test/services/rating_scale_test.rb.
module RatingScale
  SCALES = %w[one_to_five one_to_ten].freeze

  # The 1-5 scale maps to the midpoint of each equal-width 20-point band:
  # 0-19, 20-39, 40-59, 60-79, 80-100. Midpoints are unbiased, symmetric and
  # exactly invertible — 4/5 stores 70, which reads back as both 4/5 and 7/10.
  # Band starts (0/20/40/60/80) or top edges (19/39/59/79/100) are a one-line
  # swap here if the club ever prefers them.
  #
  # The 1-10 scale is a straight scale-up, so both scales round-trip.
  ENTRY_VALUES = {
    "one_to_five" => { 1 => 10, 2 => 30, 3 => 50, 4 => 70, 5 => 90 }.freeze,
    "one_to_ten" => (1..10).to_h { |value| [ value, value * 10 ] }.freeze
  }.freeze

  class << self
    # What the coach typed -> the canonical score.
    #
    # Raises rather than clamping: a score is never silently truncated the way a
    # page size is, because a truncated rating would be a wrong claim about a
    # player rather than a harmless convenience.
    def to_score(value, scale:)
      values = ENTRY_VALUES.fetch(scale.to_s) do
        raise ArgumentError, "unknown scale: #{scale.inspect}"
      end

      key = Integer(value, exception: false)
      values.fetch(key) do
        raise ArgumentError, "value #{value.inspect} is outside the #{scale} scale"
      end
    end

    # Does this value exist on that scale? The model validates through this, so
    # the band table stays in exactly one place.
    def legal_value?(value, scale:)
      ENTRY_VALUES[scale.to_s]&.key?(Integer(value, exception: false)) || false
    end

    # Canonical -> 0..10. Nil stays nil: an unrated draft must not render as a
    # score of zero.
    def to_ten(score)
      return nil if score.nil?

      [ score.to_i / 10, 10 ].min
    end

    # Canonical -> 1..5 (equal-width 20-point bands; there is no zero).
    def to_five(score)
      return nil if score.nil?

      [ (score.to_i / 20) + 1, 5 ].min
    end

    # Every scale at once, for badges and labels.
    def describe(score)
      return "Not rated yet" if score.nil?

      "#{score}/100 · #{to_ten(score)}/10 · #{to_five(score)}/5"
    end
  end
end
