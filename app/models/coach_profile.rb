# Coach-specific characteristics of a Person.
#
# A CoachProfile describes what the person is in the volleyball domain.
# Application permissions remain role-based on the User (see Role/UserRole):
# being a coach in the domain does not by itself grant administrative access.
class CoachProfile < ApplicationRecord
  STATUSES = %w[active archived].freeze

  # Visibility dimension (soft variant, same vocabulary as TrainingSession and
  # PlayerProfile): `shared` is the normal catalogue entry; `private` hides the
  # coach from other coaches' lists and detail while curators and admins still
  # see everything, and the flag never blocks scheduling. The only hard
  # ownership rule is that the switch itself may be flipped only by the owner
  # or an admin.
  VISIBILITIES = %w[shared private].freeze

  # Who recorded the coach (see PlayerProfile#created_by: the owner is stamped
  # at creation, never accepted from client params).
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :person

  # See PlayerProfile: update_only keeps a has_one update from replacing the
  # person (and creating a second identity) when no id is sent.
  accepts_nested_attributes_for :person, allow_destroy: false, update_only: true

  validates :person_id, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :visibility, presence: true, inclusion: { in: VISIBILITIES }

  # The assessments this coach recorded. See PlayerProfile#assessments: the rows
  # are the coach's professional record, so they outlive the profile — which is
  # archived rather than deleted anyway.
  has_many :assessments, dependent: :restrict_with_error

  scope :active, -> { where(status: "active") }

  # See PlayerProfile.visible_to: soft visibility for the catalogue — shared
  # profiles plus the private ones recorded by this user; curators and admins
  # see everything.
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

  # See PlayerProfile#visible_to_user?.
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
  def coach_profile_id
    id
  end

  # Published rows attributed to this coach: the number every training manager
  # may see on GET /coaches/:id. Drafts and withdrawn rows are working notes,
  # not club knowledge, so they leave the counter alone (see
  # PlayerProfile#active_assessment_count for the same reasoning).
  def assessments_recorded_count
    assessments.active.count
  end

  # The most recent published ratings this coach recorded, newest first — the
  # "recent slice" of the coach-detail payload. Rows carry Assessment#metadata,
  # the same shape the assessments endpoints serialize.
  def recent_assessments
    assessments.active.ordered
               .includes(:category, :created_by, :coach_profile, player_profile: :person)
               .limit(5)
  end

  def metadata
    {
      id: id,
      coach_profile_id: coach_profile_id,
      person_id: person_id,
      coaching_level: coaching_level,
      qualifications: qualifications,
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
