# Restores a withdrawn ranking consolidation, which only an admin may do.
#
# As with sessions the destination is chosen deliberately, and `published` is not a
# status write: it runs `RankingConsolidationPublisher`, which re-derives the
# snapshot from the current source sessions before freezing it. Reviving the old
# frozen numbers would republish a ranking that no longer matches the sessions
# behind it — and since a withdrawn source blocks publication, the publisher also
# enforces that the sources are genuinely ready to be ranked again.
class RankingConsolidationRestorer
  class Error < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join(", "))
    end
  end

  DESTINATIONS = %w[draft published].freeze

  def initialize(consolidation, to_status:)
    @consolidation = consolidation
    @to_status = to_status
  end

  def call
    raise Error, "Only a withdrawn ranking can be restored" unless @consolidation.withdrawn?
    raise Error, "Unknown destination #{@to_status}" unless DESTINATIONS.include?(@to_status)

    return restore_to_draft unless @to_status == "published"

    republish
  end

  private

  def restore_to_draft
    @consolidation.update!(status: "draft", published_at: nil)
    @consolidation
  end

  # The publisher only accepts a draft, so the record is moved there first. If the
  # republish is then refused — an unpublished or withdrawn source, say — it is
  # left as a draft, which is the honest state: the ranking is back in progress
  # rather than half-frozen.
  def republish
    @consolidation.update!(status: "draft", published_at: nil)

    begin
      RankingConsolidationPublisher.new(@consolidation).call
    rescue RankingConsolidationPublisher::Error
      @consolidation.update!(status: "draft", published_at: nil)
      raise
    end
  end
end
