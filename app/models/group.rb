# A named set of players a session can be run against — "U19 squad", "Monday
# group".
#
# A group is a *selection aid*, not an authorization boundary. It exists so a
# coach picking participants for an assessment session does not re-search twenty
# people every time; membership confers no access of its own. What it does carry
# is ownership and a leaving date, because plan §2.6 gives ownership exactly one
# source of truth and §2.5 requires memberships to be ended rather than removed.
# Those are facts about the roster, not about access.
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

  # Audit only: who recorded the row. Never consulted for authority — `owner?`
  # reads the membership instead (§2.6). Note visibility still legitimately keys
  # off this, because "private to its creator" is a presentation rule rather than
  # a statement about who may run the group.
  belongs_to :created_by, class_name: "User", optional: true

  # Membership is on Person, so the roster may hold a coach or a parent; the
  # organisation is the one that makes "these people share something" checkable.
  # Optional: see the migration — no existing group had one and none can be
  # inferred, so requiring it here would refuse every pre-existing row.
  belongs_to :organisation, optional: true

  # Membership rows only describe the roster; removing the group removes the
  # roster, which is not history in the way a session is.
  has_many :group_memberships, dependent: :destroy, inverse_of: :group
  has_many :people, through: :group_memberships
  has_many :accounts, through: :group_memberships

  # A group that has run sessions is history; deleting it is restricted so it
  # must be archived instead of leaving orphaned references.
  has_many :assessment_sessions, dependent: :restrict_with_error

  normalizes :name, with: ->(value) { value.strip.presence }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :visibility, presence: true, inclusion: { in: VISIBILITIES }

  # The decision recorded in plan §10 — a group is people who *share* an
  # Organisation — is only enforceable now that the organisation is stored. Checked
  # when it is set or changed, so re-pointing a group at an organisation whose
  # members it does not actually contain is refused at the source rather than left
  # to drift. Adding a later member goes through the same rule via
  # `#shares_organisation?`.
  validate :members_share_the_organisation,
           if: -> { organisation_id.present? && (new_record? || will_save_change_to_organisation_id?) }

  # Does every one of these people belong to the group's organisation?
  # Vacuously true when there is no organisation: the rule has nothing to check
  # against, and refusing would invent a constraint nobody asked for.
  #
  # `organisation` is overridable so a caller can ask about the state a request
  # *would* produce — a group being moved and re-rostered in one call has to be
  # checked against its new organisation, not its current one.
  def shares_organisation?(person_ids, organisation = organisation_id, account_ids: [])
    return true if organisation.nil?

    person_ids = Array(person_ids).compact.map(&:to_i).uniq
    account_ids = Array(account_ids).compact.map(&:to_i).uniq
    return true if person_ids.empty? && account_ids.empty?

    person_members = OrganisationMembership.where(organisation_id: organisation, person_id: person_ids, status: "active").distinct.count
    account_members = OrganisationMembership.where(organisation_id: organisation, account_id: account_ids, status: "active").distinct.count
    person_members == person_ids.size && account_members == account_ids.size
  end

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(:name, :id) }
  # Ownership is a membership, so "mine" is a join rather than a column match.
  # `none` rather than an unfiltered `all` when the caller has no Person, which
  # would otherwise return every group to an accountless user.
  scope :owned_by, ->(user) {
    account_id = user&.account&.id
    if account_id.nil?
      none
    else
      joins(:group_memberships)
        .where(group_memberships: { role: "owner", status: "active", account_id: account_id })
        .distinct
    end
  }

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
    return true if user.account && group_memberships.active.exists?(account_id: user.account.id)

    created_by_id.present? && created_by_id == user.id
  end

  # The single source of truth for who runs this group (§2.6). Reads the active
  # owner membership rather than `created_by_id`, so a group handed to somebody
  # else is manageable by its new owner and by nobody else. Resolved through the
  # user's Person because a group member is a Person, not an account.
  def owner?(user)
    account_id = user&.account&.id
    return false if account_id.nil?

    group_memberships.owners.exists?(account_id: account_id)
  end

  # The active owner membership, or nil. Callers that render who owns a group
  # should use this rather than re-deriving it.
  def owner_membership
    group_memberships.owners.includes(:account).first
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

  # Active members, not rows. An ended membership is history about the squad and
  # must not be counted as somebody currently in it.
  def player_count
    group_memberships.active.size
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
      # Who runs it, from the membership rather than from `created_by`, so this
      # cannot drift from what `owner?` decides.
      owner: owner_membership&.then do |membership|
        { id: membership.account_id, account_id: membership.account_id,
          name: membership.player_name }
      end,
      # Present but null for a group placed before this column existed.
      organisation: organisation && { id: organisation.id, name: organisation.name },
      # Audit only — deliberately not named "owner".
      created_by: created_by ? { id: created_by.id, name: created_by.name } : nil,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  # Every active member has to be an active member of the group's organisation.
  # Ended memberships are excluded: somebody who left the club may legitimately
  # remain on a squad's history, and counting them would make a group permanently
  # unsavable for a fact nobody can change.
  def members_share_the_organisation
    return if organisation_id.nil?

    people_ids = group_memberships.active.map(&:person_id).compact.uniq
    account_ids = group_memberships.active.map(&:account_id).compact.uniq
    return if people_ids.empty? && account_ids.empty?
    return if shares_organisation?(people_ids, organisation_id, account_ids: account_ids)

    errors.add(:organisation_id,
               "does not match everyone on the roster — a group is people who share one organisation")
  end
end
