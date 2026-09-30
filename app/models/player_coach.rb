# One period of coaching: a CoachProfile coaching a PlayerProfile.
#
# This is the *ongoing* relationship between two people, and it is deliberately
# not the same thing as an Assessment. An Assessment is one professional opinion
# recorded at a moment in time; being someone's coach is a span of time. The two
# are independent on purpose:
#
#   * a Coach does NOT need a PlayerCoach row to assess a Player — the authority
#     to record a rating is settled by the assessment rules (who the recorder is,
#     and who they attribute it to), not by whether the roster says so;
#   * ending a relationship does NOT retract or hide anything assessed during it,
#     which is why a departing coach's history stays readable.
#
# The period is expressed as dates rather than as a status flag, and the two
# invariants that follow are:
#   * `end_date IS NULL`     → still coaching;
#   * `end_date IS NOT NULL` → a historical period, kept and never deleted.
#
# A resumed relationship is a *new row*, never a reopened one. Clearing an
# `end_date` would rewrite what a past assessment was recorded against, so the
# model refuses it and the caller records a new period instead.
class PlayerCoach < ApplicationRecord
  belongs_to :player_profile
  belongs_to :coach_profile

  validates :start_date, presence: true
  validate :end_date_not_before_start_date
  validate :end_date_is_not_cleared
  validate :player_and_coach_are_different_people
  validate :one_current_period_per_pair
  validate :periods_do_not_overlap

  # `end_date IS NULL` is the definition of current, so these two scopes are the
  # whole lifecycle vocabulary — there is no `status` to keep in step.
  scope :current, -> { where(end_date: nil) }
  scope :historical, -> { where.not(end_date: nil) }
  scope :ordered, -> { order(start_date: :desc, id: :desc) }
  scope :for_player, ->(player_profile_id) { where(player_profile_id: player_profile_id) }
  scope :for_coach, ->(coach_profile_id) { where(coach_profile_id: coach_profile_id) }

  # The open period for a pair, if any. Used by the controller to answer "already
  # coaching" with a 409 instead of a validation error, and by anything that needs
  # the current roster row for a player and a coach.
  def self.current_period_for(player_profile, coach_profile)
    current.find_by(
      player_profile_id: player_profile&.id,
      coach_profile_id: coach_profile&.id
    )
  end

  def current?
    end_date.nil?
  end

  def ended?
    end_date.present?
  end

  # Was this relationship running on the given day? A period is inclusive of both
  # its dates, because a coach who ended on the 30th coached on the 30th.
  def active_on?(date)
    return false if date.nil?
    return false if start_date.nil? || date < start_date

    end_date.nil? || date <= end_date
  end

  # Ending is an update, never a delete: the row is what makes a historical
  # assessment explicable years later.
  def end!(date = Date.current)
    update!(end_date: date)
  end

  # How long the relationship ran. Nil while it is open, so a caller cannot
  # accidentally report a growing figure as a final one.
  def duration_in_days
    return nil if current? || start_date.nil?

    (end_date - start_date).to_i
  end

  def player_name
    player_profile&.person&.full_name
  end

  def coach_name
    coach_profile&.person&.full_name
  end

  # Serializable shape shared by the API and the SPA. `current` is derived, not
  # stored, so a client can never be told a relationship is running when its end
  # date says otherwise.
  def metadata
    {
      id: id,
      player_profile_id: player_profile_id,
      coach_profile_id: coach_profile_id,
      player_name: player_name,
      coach_name: coach_name,
      start_date: start_date,
      end_date: end_date,
      current: current?,
      duration_in_days: duration_in_days,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def end_date_not_before_start_date
    return if end_date.blank? || start_date.blank?
    return if end_date >= start_date

    errors.add(:end_date, "cannot be before the start date")
  end

  # The rule that makes "resume as a new period" true rather than aspirational: an
  # ended relationship may not be reopened, because the scores recorded during it
  # were recorded against that period. The caller records a new row instead.
  def end_date_is_not_cleared
    return unless persisted?
    return unless will_save_change_to_end_date?

    before, after = end_date_change
    return unless before.present? && after.nil?

    errors.add(:end_date, "cannot be cleared; a resumed relationship is a new period")
  end

  # Mirrors Assessment's own rule: a person does not coach themselves. Stated here
  # too because a relationship is keyed on two profiles and one Person may hold
  # both, so the check has to look through to `person_id`.
  def player_and_coach_are_different_people
    return if player_profile.blank? || coach_profile.blank?
    return unless player_profile.person_id == coach_profile.person_id

    errors.add(:coach_profile, "cannot be the same person as the player")
  end

  # Mirrors the partial unique index, so a duplicate produces a message rather
  # than a raw constraint violation. The index remains the real guard: this check
  # loses to a race, the index does not.
  def one_current_period_per_pair
    return unless current?
    return if player_profile_id.blank? || coach_profile_id.blank?

    rival = self.class.current.where(
      player_profile_id: player_profile_id,
      coach_profile_id: coach_profile_id
    )
    rival = rival.where.not(id: id) if persisted?

    return if rival.none?

    errors.add(:player_profile, "already has an open coaching relationship with this coach")
  end

  # Two periods for the same pair may not overlap. Without this, "how many coaches
  # did this player have in March?" has two answers.
  def periods_do_not_overlap
    return if start_date.blank?
    return if player_profile_id.blank? || coach_profile_id.blank?

    rival = self.class.where(
      player_profile_id: player_profile_id,
      coach_profile_id: coach_profile_id
    )
    rival = rival.where.not(id: id) if persisted?
    # An open period has no upper bound, so it only has to start before this one
    # ends — which is what "end_date IS NULL OR end_date >= start_date" expresses.
    rival = rival.where("start_date <= ?", end_date) if end_date.present?
    rival = rival.where("end_date IS NULL OR end_date >= ?", start_date)

    return if rival.none?

    errors.add(:start_date, "overlaps another coaching period for this player and coach")
  end
end
