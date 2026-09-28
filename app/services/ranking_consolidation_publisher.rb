# Publishes a draft ranking consolidation, freezing it as the club's official
# ranking.
#
# The gate is the product rule: a consolidation may only be published once
# *every* source session is published. A ranking assembled over half-finished
# sessions is a draft, never an official claim about real athletes.
#
# Two things happen in one transaction, and the order matters:
#
#   1. `refresh!` re-derives the snapshot and rows from the current source
#      sessions. A draft session's scores will have moved since the consolidation
#      was built, so publishing the original snapshot would freeze a ranking that
#      disagrees with the sessions behind it. Refreshing *before* freezing is what
#      makes "published" trustworthy.
#   2. the status flips to published with a timestamp, after which `refresh!`
#      refuses to run again (D24).
#
# Refusals are 422s carrying the session names, because "cannot publish" without
# saying which session is unfinished leaves the coach with nothing to act on.
class RankingConsolidationPublisher
  class Error < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join(", "))
    end
  end

  def initialize(consolidation)
    @consolidation = consolidation
  end

  def call
    raise Error, "This ranking is already published" if @consolidation.published?
    # A withdrawn ranking is a retraction, and only `restore` may undo one. Without
    # this guard `publish` would be a second, author-reachable way out of the
    # withdrawn state — which would make withdrawal reversible by its own author
    # and the admin-only rule meaningless.
    if @consolidation.withdrawn?
      raise Error, "This ranking was withdrawn and can only be restored by an admin"
    end

    # A withdrawn *source* no longer blocks publishing: it contributes no scores,
    # so the ranking is still complete and honest. The only thing still forbidden
    # is a consolidation with nothing left to rank at all.
    if @consolidation.withdrawn_source_sessions.size == @consolidation.consolidation_sessions.size
      raise Error, "Every source session has been withdrawn, so there is nothing to rank"
    end

    raise Error, "This ranking has no source sessions" if @consolidation.consolidation_sessions.empty?

    pending = @consolidation.unpublished_source_sessions
    if pending.any?
      raise Error, pending.map { |session|
        "Session \"#{session.name}\" is #{session.status}, not published"
      }
    end

    RankingConsolidation.transaction do
      # Re-read from the current sources first, so the frozen numbers are the ones
      # the published sessions actually produce right now.
      RankingConsolidationBuilder.new(
        assessment_definition: @consolidation.assessment_definition
      ).refresh!(@consolidation)

      @consolidation.update!(status: "published", published_at: Time.current)
    end

    @consolidation
  end
end
