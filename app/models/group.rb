# A named set of players a session can be run against — "U19 squad", "Monday
# group".
#
# A group is a *selection aid*, not an authorization boundary. It exists so a
# coach picking participants for an assessment session does not re-search twenty
# people every time; membership confers no access of its own. That is why the
# join carries no status and why the only ownership rule here is the soft
# visibility switch the rest of the catalogue already uses.
#
# Archive-not-delete: a group that has been used to run sessions is history, so
# it becomes `archived` rather than disappearing from under the sessions that
# named it.
class Group < ApplicationRecord
  include Sluggable
  source_column :name

  STATUSES = %w[active archived].freeze

  # Same vocabulary and same reasoning as PlayerProfile: `shared` is the normal
  # case, `private` keeps a group to its creator while curators and admins still
  # see everything. Soft means *presentation*, never authorization.
  VISIBILITIES = %w[shared private].freeze

  belongs_to :created_by, class_name: "User", optional: true

  # Membership rows only describe the roster; removing the group removes the
  # roster, which is not history in the way a session is.
  has_many :group_memberships, dependent: :destroy, inverse_of: :group
  has_many :player_profiles, through: :group_memberships

  # A group that has run sessions is history; deleting it is restricted so it
  # must be archived instead of leaving orphaned references.
  has_many :assessment_sessions, dependent: :restrict_with_error

  normalizes :name, with: ->(value) { value.strip.presence }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :visibility, presence: true, inclusion: { in: VISIBILITIES }

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(:name, :id) }
  scope :owned_by, ->(user) { where(created_by_id: user&.id) }

  # The catalogue lists active groups; a private group is visible to the person
  # who recorded it, and curators/admins see everything — the same pair
  # PlayerProfile#visible_to treats as unlimited.
  scope :visible_to, ->(user) {
    return all if user.nil?
    return all if user.admin? || user.curator?

    where(visibility: "shared").or(where(created_by_id: user.id))
  }

  def visible_to_user?(user)
    return true if shared?
    return true if user.nil?
    return true if user.admin? || user.curator?

    created_by_id.present? && created_by_id == user.id
  end

  def owner?(user)
    user.present? && created_by_id.present? && created_by_id == user.id
  end

  def archived?
    status == "archived"
  end

  def shared?
    visibility == "shared"
  end

  def private?
    visibility == "private"
  end

  def status_label
    status.to_s.capitalize
  end

  def player_count
    group_memberships.size
  end

  def metadata
    {
      id: id,
      name: name,
      slug: slug,
      description: description,
      visibility: visibility,
      status: status,
      status_label: status_label,
      player_count: player_count,
      created_by: created_by ? { id: created_by.id, name: created_by.name } : nil,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end
