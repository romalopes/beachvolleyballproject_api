class AssessmentSession < ApplicationRecord
  STATUSES = %w[draft published withdrawn].freeze

  belongs_to :assessment_definition
  belongs_to :coach_profile
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :group, optional: true

  has_many :participants,
           class_name: "AssessmentSessionParticipant",
           dependent: :destroy,
           inverse_of: :assessment_session
  has_many :assessments, dependent: :nullify

  has_many :consolidation_sessions,
           class_name: "RankingConsolidationSession",
           dependent: :destroy,
           inverse_of: :assessment_session

  # A draft is a work in progress, not history, so deleting one takes its own
  # draft results with it — otherwise a discarded screen leaves unrated rows
  # floating in the catalogue attached to no session at all.
  #
  # `prepend: true` is required, not cosmetic. `dependent: :nullify` registers
  # its own before_destroy earlier, and by the time an ordinary callback runs
  # the session ids are already gone, so the rows this must remove can no
  # longer be identified as belonging to this session. Prepending runs first.
  #
  # A published session is archival, so `dependent: :nullify` governs the
  # assessments in that case: the result survives with a null session, which
  # assessment_session_test.rb pins.
  before_destroy :discard_own_draft_results, prepend: true, if: :draft?

  # Admins may hard-delete a published session, and a consolidation that sourced
  # it must not be destroyed along with it. The restrictive foreign key would
  # otherwise raise. A published consolidation is unaffected — its rows and
  # snapshot are self-contained frozen data (D24) — while a draft one now rests
  # on fewer sessions, so it is told why.
  before_destroy :detach_from_consolidations, prepend: true

  validates :status, inclusion: { in: STATUSES }
  validates :assessment_definition, :coach_profile, presence: true
  validate :definition_must_be_active, on: :create
  validate :published_at_must_be_present, if: :published?

  scope :ordered, -> { order(scheduled_on: :desc, created_at: :desc) }

  def draft?
    status == "draft"
  end

  def published?
    status == "published"
  end

  def withdrawn?
    status == "withdrawn"
  end

  # A withdrawal is a retraction, so it is only reachable from published: a draft
  # is discarded by deleting it, and a withdrawn session is already retracted.
  def withdrawable?
    published?
  end

  # Only an admin restores a withdrawn session, and the destination is chosen by
  # the caller. Returning to `published` is NOT a plain status write — it must go
  # through AssessmentSessionPublisher so the session's assessments are activated
  # again. Flipping the column alone would leave a published session whose results
  # are still drafts, and a ranking built on it would score nothing.
  def restorable?
    withdrawn?
  end

  def included_participants
    participants.included
  end

  private

  # A draft session's results are drafts by construction: publishing is what
  # activates them. So removing the session removes them, and nothing that was
  # ever published is touched. The status filter is belt-and-braces — a stale
  # "active" row would mean publish ran twice, and that is history, not scratch.
  def discard_own_draft_results
    assessments.where(status: "draft").destroy_all
  end

  # Removing this session must leave every consolidation that referenced it
  # standing, with the reason recorded rather than silently swallowed.
  #
  # A published consolidation keeps its frozen rows and snapshots untouched — the
  # session was only ever a pointer to them, and that is the whole point of D24.
  # A draft consolidation, though, re-derives from its sources at publish time,
  # so a detached source silently changes the ranking it would produce. This
  # `source_warnings` entry is the only record that it now rests on fewer
  # sessions than were originally chosen; a published one is never rewritten.
  def detach_from_consolidations
    consolidation_sessions.includes(:ranking_consolidation).each do |join|
      consolidation = join.ranking_consolidation
      next if consolidation.nil? || consolidation.published?

      consolidation.update!(
        source_warnings: consolidation.source_warnings + [ {
          assessment_session_id: id,
          name: name,
          incomplete_count: 0,
          incomplete_players: [],
          reason: "source_session_deleted"
        } ]
      )
    end
  end

  def definition_must_be_active
    return if assessment_definition&.status == "active"

    errors.add(:assessment_definition, "must be active")
  end

  def published_at_must_be_present
    errors.add(:published_at, "must be present when publishing") if published_at.blank?
  end
end
