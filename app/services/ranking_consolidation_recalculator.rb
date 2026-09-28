# Recalculates a published ranking so that a source session withdrawn *after* it
# was published stops contributing.
#
# This is the deliberate, supervised exception to the immutability of a published
# consolidation (D24). The exception is narrow on purpose:
#
#   * A withdrawal never cascades. Publishing does not change when a source is
#     retracted, so the ranking keeps its figures until someone acts here.
#   * Only oversight (curator/admin) may do it, because it rewrites a result other
#     people may already have acted on.
#   * It needs a reason. `recalculable?` is false unless a source was withdrawn
#     after the snapshot was computed, so this cannot be used to churn a correct
#     ranking.
#   * It is recorded. `recalculated_at`/`recalculated_by_id` say when and by whom,
#     and `published_at` is left alone — it answers "when did this become the
#     club's result", which a later correction does not change.
#
# The rebuild is the same `refresh!` the publisher uses, so a recalculated ranking
# is produced by exactly one code path.
class RankingConsolidationRecalculator
  class Error < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join(", "))
    end
  end

  def initialize(consolidation, current_user:)
    @consolidation = consolidation
    @current_user = current_user
  end

  def call
    # Checked before the published gate, because a withdrawn ranking is not a draft
    # to be published — it is a retraction that `restore` ends. Reporting it as "not
    # published" would send the caller to the wrong action.
    raise Error, "A withdrawn ranking can only be restored, not recalculated" if @consolidation.withdrawn?
    raise Error, "Only a published ranking can be recalculated" unless @consolidation.published?

    stale = @consolidation.stale_withdrawn_source_sessions
    restored = @consolidation.restored_source_sessions
    if stale.empty? && restored.empty?
      raise Error, "There is nothing to recalculate — no source has changed since this ranking was published"
    end

    # Nothing left to rank would publish an empty result that reads as "nobody was
    # scored", so it is refused here exactly as it is at publish time. Counted on what
    # the rebuild would actually skip, not on what is withdrawn now: a restored source
    # is published and scores again, so it makes the result rankable rather than empty.
    if rankable_source_count.zero?
      raise Error, "Every source session has been withdrawn, so there is nothing to rank"
    end

    RankingConsolidation.transaction do
      RankingConsolidationBuilder.new(
        assessment_definition: @consolidation.assessment_definition
      ).refresh!(@consolidation, force: true)

      # Stamped after the rebuild so `computed_at` is later than the withdrawals it
      # now accounts for — otherwise the next read would still call them stale.
      @consolidation.update!(
        recalculated_at: Time.current,
        recalculated_by: @current_user
      )
    end

    @consolidation
  end

  private

  # How many sources the rebuild would actually rank: everything except the ones that
  # are still withdrawn. A restored source counts, because restoring it is the whole
  # reason a recalculation is being offered.
  def rankable_source_count
    @consolidation.assessment_sessions.count { |s| !s.withdrawn? }
  end
end
