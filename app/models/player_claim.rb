# A reviewable request to attach a claimant Person to a subject the club already
# recorded. Claiming changes only the link; the subject row and all of its domain
# history stay exactly where they are.
#
# `claimable` is polymorphic (PlayerProfile, CoachProfile or Person). The legacy
# `player_profile_id` column is retained for existing rows and clients: a claim
# carries exactly one of the two, enforced by a check constraint. An Account-aware
# partial unique index prevents duplicate pending claims by the same Account while
# allowing separate Accounts to submit competing claims.
#
# The model name still says "Player" for continuity with the API and the table;
# see IDENTITY_PHASE_18_UNIFIED_CLAIMS.md for the naming follow-up.
class PlayerClaim < ApplicationRecord
  STATUSES = %w[pending approved rejected cancelled].freeze

  belongs_to :claimable, polymorphic: true, optional: true
  belongs_to :player_profile, optional: true
  belongs_to :person
  belongs_to :initiated_by_person, class_name: "Person"
  belongs_to :reviewed_by_person, class_name: "Person", optional: true
  belongs_to :claimant_account, class_name: "Account", optional: true
  belongs_to :reviewed_by_account, class_name: "Account", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :reviewed_at, presence: true, if: -> { %w[approved rejected].include?(status) }
  validates :reviewed_by_person, presence: true, if: -> { %w[approved rejected].include?(status) }
  validates :rejection_reason, presence: true, if: -> { status == "rejected" }
  validate :exactly_one_subject

  scope :pending, -> { where(status: "pending") }

  # Pending claims whose subject is a profile this user recorded. Phrased
  # against the polymorphic columns rather than `player_profiles:` because the
  # Phase 18 migration clears `player_profile_id` — an inner join on it would
  # silently hide every migrated claim from the review queue.
  #
  # Written as SQL rather than `union`, which an ActiveRecord::Relation does not
  # expose, because the two subject kinds live in different tables and their ids
  # may coincide.
  scope :pending_for_owner, ->(user) {
    pending.where(
      "(claimable_type = 'PlayerProfile' AND claimable_id IN " \
      "(SELECT id FROM player_profiles WHERE created_by_id = :uid OR created_by_account_id = :aid)) OR " \
      "(claimable_type = 'CoachProfile' AND claimable_id IN " \
      "(SELECT id FROM coach_profiles WHERE created_by_id = :uid OR created_by_account_id = :aid))",
      uid: user.id, aid: user.account&.id
    )
  }

  def pending? = status == "pending"

  # The subject, whichever column carries it.
  def subject
    claimable || player_profile
  end

  # The player-profile id, for the API's back-compat key. After the Phase 18
  # migration every claim stores its subject in the polymorphic pair and leaves
  # `player_profile_id` NULL, so this cannot just read the column.
  def player_profile_key
    return player_profile_id if player_profile_id.present?

    claimable_type == "PlayerProfile" ? claimable_id : nil
  end

  def subject_type
    claimable_type || (player_profile_id.present? ? "PlayerProfile" : nil)
  end

  # May `user` review this claim? An admin may review any; a coach only the
  # profiles they recorded. Reads `subject`, so it stays correct for a migrated
  # claim whose `player_profile_id` is NULL.
  def reviewable_by?(user)
    return false unless subject.is_a?(PlayerProfile) || subject.is_a?(CoachProfile)

    ProfilePolicy.new(actor: user, profile: subject).review_claim?
  end

  # Human label for review queues and audit text.
  def subject_label
    return nil unless subject

    subject_type == "PlayerProfile" ? "player profile" : ClaimSubject.for(subject).label
  end

  # `include_profile_name` is the historic keyword; the subject name is shown
  # instead when the caller may see it.
  def summary(include_profile_name: false)
    result = {
      id: id,
      player_profile_id: player_profile_key,
      claimable_type: claimable_type,
      claimable_id: claimable_id,
      person_id: person_id,
      status: status,
      created_at: created_at,
      reviewed_at: reviewed_at
    }
    result[:player_name] = subject&.full_name if include_profile_name
    result
  end

  private

  def exactly_one_subject
    both = claimable_id.present? && player_profile_id.present?
    neither = claimable_id.nil? && player_profile_id.nil?
    errors.add(:base, "A claim must name exactly one subject") if both || neither
  end
end
