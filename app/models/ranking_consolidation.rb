# Phase 4 (Ranking Consolidation), plan §8: a club-level ranking merging
# several coaches' session results into one snapshot.
#
# A consolidation is a *draft* until it is published, then archival (D24). The
# two-phase lifecycle exists because a club ranking is assembled from several
# coaches' sessions that are often still being scored: a coach needs to gather
# them first and publish once. While it is a draft the snapshot is re-derivable
# — `RankingConsolidationBuilder#refresh!` re-reads the sources — and publishing
# freezes it. Immutability starts at publish, not at creation, so a published
# ranking can never disagree with the sessions it was built from.
#
# `source_warnings` is why this record stays honest without re-reading the
# sources: under D21 a merge never blocks over missing or incomplete players,
# so the consolidation instead carries the per-session reasons it merged
# anyway. Set by the builder, never recomputed on read.
class RankingConsolidation < ApplicationRecord
  STATUSES = %w[draft published withdrawn].freeze

  belongs_to :assessment_definition
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :recalculated_by, class_name: "User", optional: true

  has_many :consolidation_sessions,
           class_name: "RankingConsolidationSession",
           dependent: :destroy,
           inverse_of: :ranking_consolidation
  has_many :assessment_sessions, through: :consolidation_sessions
  has_many :rows,
           class_name: "RankingConsolidationRow",
           dependent: :destroy,
           inverse_of: :ranking_consolidation

  validates :assessment_definition, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  # A published row that cannot say when it was published is a claim nobody can
  # date, so the model refuses it rather than letting the API hand one out.
  validates :published_at, presence: true, if: :published?

  scope :ordered, -> { order(created_at: :desc, id: :desc) }
  scope :drafts, -> { where(status: "draft") }

  def draft?
    status == "draft"
  end

  def published?
    status == "published"
  end

  def withdrawn?
    status == "withdrawn"
  end

  # A withdrawal is a retraction, so only a published record can be retracted: a
  # draft is discarded by deleting it, and an already-withdrawn record has nothing
  # left to retract.
  def withdrawable?
    published?
  end

  # Only an admin restores a withdrawn consolidation. The destination is the
  # caller's choice, and returning to `published` must go through
  # RankingConsolidationPublisher so the snapshot is re-derived rather than revived
  # exactly as it was when it was retracted.
  def restorable?
    withdrawn?
  end

  def status_label
    status.to_s.capitalize
  end

  # Source sessions that are not published. This is what gates publishing: a
  # consolidation built over half-finished sessions is a draft, never a club
  # ranking. Names come back so the coach knows which session to go and finish.
  #
  # Withdrawn is deliberately *excluded* from this list. A withdrawn session is a
  # retraction the club already knows about, and it contributes no scores to the
  # merge, so it cannot make a ranking wrong. Treating it as a blocker would strand
  # a consolidation whose only unfinished source is one nobody will ever finish.
  def unpublished_source_sessions
    assessment_sessions.reject { |s| s.published? || s.withdrawn? }.sort_by(&:id)
  end

  # Withdrawn sources, listed separately so the UI can tell the coach which
  # sessions are being left out of the ranking, and why.
  def withdrawn_source_sessions
    assessment_sessions.select(&:withdrawn?).sort_by(&:id)
  end

  # Sessions that actually contribute scores. A withdrawn source is excluded, so
  # this — not the raw source count — is the denominator for coverage: a player
  # ranked by every *contributing* session has full coverage. Counting a withdrawn
  # session would report every player as under-covered for no fault of their own.
  def contributing_source_sessions
    assessment_sessions.reject(&:withdrawn?)
  end

  def publishable?
    draft? && unpublished_source_sessions.empty? && consolidation_sessions.any?
  end

  # When this snapshot was computed from live sources: the original publication, or
  # a later supervised recalculation.
  #
  # This is the only sound basis for asking whether a withdrawn session is already
  # out of the numbers. Comparing live status against a frozen snapshot cannot work,
  # because the two can only ever agree if nothing happened in between — which is
  # precisely the case a coach needs to be told about. `published_at` is deliberately
  # not moved by a recalculation: it answers "when did this become the club's
  # result", which a later correction does not change.
  def computed_at
    recalculated_at || published_at
  end

  # Withdrawn sources whose scores are genuinely absent from this snapshot — retracted
  # before the ranking was computed, so the merge already skipped them.
  def excluded_withdrawn_source_sessions
    withdrawn_source_sessions.select { |s| excluded_from_snapshot?(s) }
  end

  # Withdrawn sources that are *still counted* in this snapshot, because the retraction
  # happened after the ranking was frozen. Publishing does not cascade, so these numbers
  # stay as they are until somebody deliberately recalculates — which is the only honest
  # reading of "the ranking does not change".
  def stale_withdrawn_source_sessions
    withdrawn_source_sessions.reject { |s| excluded_from_snapshot?(s) }
  end

  # Recalculating is a supervised correction to an otherwise immutable published
  # ranking, so it needs something to correct: without a stale source it would rewrite
  # identical numbers for no reason.
  def recalculable?
    published? && stale_withdrawn_source_sessions.any?
  end

  private

  # A source counts as excluded when it was already withdrawn when this snapshot was
  # computed. A draft has no frozen snapshot yet, so everything withdrawn is simply
  # excluded — that is what the build will skip.
  def excluded_from_snapshot?(session)
    return true unless computed_at

    session.updated_at <= computed_at
  end
end
