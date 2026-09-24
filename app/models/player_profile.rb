# Player-specific characteristics of a Person.
#
# This is a domain descriptor, not an authorization role and not an
# authentication record: contact and credential data live on Person/Account.
class PlayerProfile < ApplicationRecord
  STATUSES = %w[active archived].freeze

  # Visibility dimension (soft variant, same vocabulary as TrainingSession):
  #   * shared  — the normal case: every training manager sees the player in
  #     the catalogue;
  #   * private — hidden from other coaches' lists and detail, so a coach can
  #     keep a player to themselves. Curators and admins still see everything,
  #     and the flag never blocks scheduling: any coach can add any player to
  #     any session. Soft means *presentation*, not authorization — the only
  #     hard ownership rule is that the visibility switch itself may be flipped
  #     only by the owner or an admin.
  VISIBILITIES = %w[shared private].freeze

  # `created_by` is the owner recorded at creation: the FK is stamped from the
  # authenticated request (see the create actions), and never accepted from
  # the client — mass-assignment from `player_params`/`coach_params` does not
  # include it, so neither create nor update can set it from the payload.
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :person

  # `update_only: true` is essential: for a has_one, Rails otherwise *replaces*
  # the person instead of updating it whenever the nested hash carries no id,
  # which would silently create a second identity on every contact-detail edit.
  # With update_only the existing person is updated in place, and a profile
  # created without one still builds a new person.
  accepts_nested_attributes_for :person, allow_destroy: false, update_only: true

  has_many :training_session_participants, dependent: :destroy, inverse_of: :player_profile

  # Assessments are the player's coaching history, so a profile may never be
  # destroyed while they exist: the row is the evidence a coach recorded, and
  # history that can vanish is history nobody can trust. Profiles leave the
  # catalogue by becoming `archived` instead of being deleted (see the
  # archive-not-delete rule), so this only guards a mistake.
  has_many :assessments, dependent: :restrict_with_error

  validates :person_id, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :visibility, presence: true, inclusion: { in: VISIBILITIES }

  scope :active, -> { where(status: "active") }

  # Soft visibility for the catalogue: a training manager sees the shared
  # profiles plus the private ones they recorded themselves. This is the
  # project's first ownership boundary, deliberately overriding the sessions'
  # "role-based only" convention: a session created yesterday by one coach
  # must stay manageable by the others, but a player a coach keeps private
  # must not appear in another coach's list.
  scope :visible_to, ->(user) {
    return all if user.nil?
    return all if user.admin? || user.curator?

    where(visibility: "shared").or(where(created_by_id: user.id))
  }
  scope :owned_by, ->(user) { where(created_by_id: user.id) }

  def shared?
    visibility == "shared"
  end

  def private?
    visibility == "private"
  end

  # Single source of truth for "may this user see this profile?" — the
  # catalogue, the detail endpoints and any future caller must use this
  # instead of reimplementing the rules.
  def visible_to_user?(user)
    return true if shared?
    return true if user.nil?
    return true if user.admin? || user.curator?

    created_by_id.present? && created_by_id == user.id
  end

  def owner?(user)
    user.present? && created_by_id.present? && created_by_id == user.id
  end

  # Only the owner or an admin may flip the visibility switch.
  def visibility_change_permitted?(user)
    user.present? && (user.admin? || owner?(user))
  end

  def full_name
    person.full_name
  end

  def account_status
    person.account_status
  end

  # API-facing alias: callers address a profile by `<resource>_profile_id`
  # (training session participants already use that shape), so payloads carry
  # both the generic `id` and this domain-specific key.
  def player_profile_id
    id
  end

  # Number of training sessions this player has been invited to. Part of the
  # player-detail payload (training history); callers should eager load
  # training_session_participants to avoid an extra query.
  def training_session_count
    training_session_participants.size
  end

  # Published coaching history only: `assessment_count` and the `assessments`
  # slice on GET /players/:id count what every training manager may see.
  # Drafts and withdrawn rows are someone's working notes, not club knowledge,
  # and they leave these counters alone. Callers who feed them into a user
  # payload should still apply `visible_to(user)` first — the public status
  # is necessary but not sufficient, because the assessed player may be
  # private to the caller.
  def active_assessment_count
    assessments.active.count
  end

  # Latest published rating per rubric, newest first. "Per rubric" means the
  # category's id, or — when the rubric is free text — the text itself, so two
  # `custom_category` rows never collapse into one entry. Only one assessment
  # runs at a time here (the SPA renders a handful of rows), so the grouping
  # stays in Ruby where the reader can see it.
  def latest_rated_assessments
    assessments.active.ordered.includes(:category, :created_by, :coach_profile).group_by(&:rubric_key).map do |_, rows|
      rows.max_by(&:created_at)
    end.sort_by(&:created_at).reverse
  end

  def metadata
    {
      id: id,
      player_profile_id: player_profile_id,
      person_id: person_id,
      preferred_position: preferred_position,
      level: level,
      status: status,
      visibility: visibility,
      created_by: created_by ? { id: created_by.id, name: created_by.name } : nil,
      full_name: full_name,
      account_status: account_status,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end
