# Restores a withdrawn assessment session, which only an admin may do.
#
# `to_status` is explicit rather than a boolean, because the two destinations are
# genuinely different operations and the caller has to choose deliberately:
#
#   "draft"     — puts the session back in progress. The coach rescores it and
#                 publishes again on their own terms.
#   "published" — republishes it. This is NOT a status write: it runs the
#                 publisher so the session's assessments are re-activated. A
#                 plain `update!` would leave a published session whose results
#                 are still drafts, and any ranking built on it would score
#                 nothing at all.
#
# Refusals raise with 422 semantics. Republishing goes through
# `AssessmentSessionPublisher`, so it is refused exactly as a first publication
# would be — most importantly, a session with unscored players cannot be
# published, and a restored-but-unscored session is exactly the trap.
class AssessmentSessionRestorer
  class Error < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join(", "))
    end
  end

  DESTINATIONS = %w[draft published].freeze

  def initialize(session, to_status:)
    @session = session
    @to_status = to_status
  end

  def call
    raise Error, "Only a withdrawn session can be restored" unless @session.withdrawn?
    raise Error, "Unknown destination #{@to_status}" unless DESTINATIONS.include?(@to_status)

    return restore_to_draft unless @to_status == "published"

    republish
  end

  private

  def restore_to_draft
    @session.update!(status: "draft", published_at: nil)
    @session
  end

  # Delegating to the publisher is what makes this safe: the draft→published
  # transition already knows how to refuse a session that is not ready, and
  # reusing it means a restore can never be more permissive than a first
  # publication. The flip to draft happens first because the publisher only ever
  # accepts a draft, and it is the same transaction the session would have had.
  def republish
    AssessmentSession.transaction do
      @session.update!(status: "draft", published_at: nil)
    end

    begin
      AssessmentSessionPublisher.new(@session).call
    rescue AssessmentSessionPublisher::Error
      # Leave the session in draft rather than half-published: a withdrawn
      # session that was not ready to come back belongs in progress, and the
      # admin can fix the scores there.
      @session.update!(status: "draft", published_at: nil)
      raise
    end
  end
end
