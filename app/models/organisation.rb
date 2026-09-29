# A hierarchical organisational entity — an international federation, a national
# body, a state association, a club, an academy, a school.
#
# One table and one self-reference, never a table per level: the depth is
# unbounded and nothing downstream may assume a fixed number of tiers. A club and
# an academy are the *same kind of row* that happens to sit lower in the tree, which
# is why `organisation_type` is a label and never a branch in business logic.
#
# Archive-not-delete, matching Group and AssessmentSession: an organisation that
# has run sessions or owned a ranking is history, so it becomes `archived` rather
# than disappearing from under the records that named it.
#
# Hierarchy is context, not access. Being a member of a national federation says
# nothing about who may read a private assessment belonging to a club at the bottom
# of the tree — that grant is made explicitly elsewhere, never inferred from depth.
class Organisation < ApplicationRecord
  include Sluggable
  source_column :name

  # Archive-not-delete, using the same vocabulary as every other lifecycle here
  # rather than an `archived_at` column, so the state is queryable in one place.
  STATUSES = %w[active archived].freeze

  # Free-form. Intentionally open: a new kind of organisation is a row value, not a
  # migration, and nothing may branch on it (see the class comment).
  ORGANISATION_TYPES = %w[
    international_federation
    national_federation
    state_federation
    club
    academy
    school
    association
    other
  ].freeze

  NAME_MAX_LENGTH = 120
  # Short enough to be a badge or a fallback tile. An acronym longer than this is
  # an abbreviation nobody uses.
  ACRONYM_MAX_LENGTH = 12

  # Logo limits, mirroring Producer in the sibling wine_prediction_api project so
  # an uploaded logo behaves identically across both applications.
  MAX_LOGO_SIZE = 10.megabytes
  # A hard ceiling on the stored image, enforced rather than merely declared: an
  # unbounded logo is a real cost when a browser scales it down for a list row.
  MAX_LOGO_DIMENSION = 5000
  ALLOWED_LOGO_TYPES = %w[
    image/png image/jpeg image/gif image/webp image/svg+xml
  ].freeze

  belongs_to :parent_organisation, class_name: "Organisation", optional: true
  belongs_to :created_by_person, class_name: "Person", optional: true

  # The first attachment in this application. The storage service was already
  # configured but never installed, so this is what the Active Storage tables
  # exist for.
  has_one_attached :logo

  # Membership is the only record of who belongs to an organisation, and it is also
  # the single source of truth for *ownership*. `created_by_person_id` is audit
  # only — who recorded the row — so there are never two competing answers to "who
  # owns this club", which is how a transferred club ends up unmanageable by anyone.
  has_many :organisation_memberships, dependent: :destroy
  # `members` means *current* members. Going through the raw association would
  # include people who had left, so "is this person one of ours?" would keep
  # answering yes after they resigned — the ended rows stay for history, and this
  # is how callers read the present.
  has_many :active_memberships,
           -> { active },
           class_name: "OrganisationMembership",
           inverse_of: :organisation
  has_many :members, through: :active_memberships, source: :person

  has_many :child_organisations,
           class_name: "Organisation",
           foreign_key: :parent_organisation_id,
           dependent: :restrict_with_error,
           inverse_of: :parent_organisation

  normalizes :name, with: ->(value) { value.strip.presence }
  # An acronym is a display short form, so it is stored the way it is shown:
  # upcased, trimmed, and empty rather than a blank string. "FIVB" and "fivb"
  # are the same short form, and a blank one must read as absent.
  normalizes :acronym, with: ->(value) { value.strip.upcase.presence }

  validates :name, presence: true,
                   length: { maximum: NAME_MAX_LENGTH },
                   uniqueness: { case_sensitive: false }
  # Optional, but bounded and shaped. An acronym is a short display form, so
  # anything that is not a compact label — a full sentence, a URL, an
  # accented word — is a mistake worth refusing rather than rendering. Permissive
  # enough for the forms that genuinely exist: "FIVB", "VB NSW", "C.B.V.A.".
  #
  # Explicit ASCII rather than Ruby's `[[:alnum:]]`, which matches Unicode letters
  # and so would have accepted "FÉDÉRATION" — a capitalised word, not an acronym.
  # Acronyms are conventionally ASCII even inside a non-English organisation: the
  # governing body here is French-named and is still FIVB, not FÉDÉRATION.
  validates :acronym,
            length: { maximum: ACRONYM_MAX_LENGTH },
            format: {
              with: /\A[A-Za-z0-9][A-Za-z0-9 .&'-]*\z/,
              message: "may contain only letters, numbers, spaces, dots, dashes and ampersands"
            },
            allow_blank: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :organisation_type, presence: true, inclusion: { in: ORGANISATION_TYPES }
  validate :parent_must_not_be_self
  validate :parent_must_not_create_a_cycle
  validate :logo_content_type_size_and_dimensions, if: -> { logo.attached? }

  scope :active, -> { where(status: "active") }
  scope :ordered, -> { order(:name, :id) }
  scope :roots, -> { where(parent_organisation_id: nil) }
  scope :of_type, ->(type) { type.present? ? where(organisation_type: type) : all }
  # A blank filter is "no filter" rather than "nothing matches", so an index call
  # without a status returns everything rather than an empty page.
  scope :with_status, ->(status) { status.present? ? where(status: status) : all }

  def archived?
    status == "archived"
  end

  def active?
    status == "active"
  end

  def status_label
    status.to_s.capitalize
  end

  def root?
    parent_organisation_id.nil?
  end

  def archivable?
    !archived?
  end

  def restorable?
    archived?
  end

  # --- membership ------------------------------------------------------------

  # The organisation's owner, read from the membership rather than from
  # `created_by_person_id`. An organisation can be handed over, and only one of
  # these can change when that happens.
  def owner
    active_memberships.find_by(role: "owner")&.person
  end

  def owner?(person)
    return false if person.nil?

    active_memberships.where(role: "owner", person_id: person.id).exists?
  end

  # Whether a person may change this organisation's membership: its owner and its
  # administrators. An ordinary member — however senior — may not, so a club's
  # roster cannot be rewritten by the people it is a roster of.
  #
  # Site admins are *not* handled here; that is a wider authority than membership
  # and belongs to the authorization layer, which ORs the two.
  def manageable_by?(person)
    return false if person.nil?

    person.organisation_memberships.active
                                   .manageable
                                   .exists?(organisation_id: id)
  end

  def active_organisation_memberships
    active_memberships
  end

  def member_count
    active_organisation_memberships.count
  end

  # Whether a person may edit the organisation's own record: its name, its
  # description, its logo.
  #
  # Three sources, and they are deliberately different kinds of claim:
  #
  #   * the *current* owner and administrators, who run the organisation and must
  #     be able to correct what it says about itself;
  #   * whoever created it, **but only while they are still a member**. The
  #     creator grant is recorded on a Person and is never cleared, so keying on it
  #     alone would let a founder who resigned keep renaming the club forever while
  #     their roster rights had correctly lapsed. Membership is what expires it.
  #
  # Site admins and curators are not handled here: those are wider authorities and
  # the authorization layer ORs them in.
  def editable_by?(person)
    return false if person.nil?
    return true if manageable_by?(person)
    return false unless created_by_person_id == person.id

    person.organisation_memberships.active.exists?(organisation_id: id)
  end

  # Whether this organisation may be hard-deleted at all.
  #
  # Archive is the normal way to retire one. A hard delete is for a *mistake* — a
  # club created twice, a placeholder that was never used — and the two conditions
  # below are what make that distinction real rather than a matter of intent:
  #
  #   * no child organisations. A node with children cannot be removed without
  #     either orphaning a branch or silently re-parenting it, and neither is
  #     something a delete button should do on its own. `child_organisations` is
  #     `restrict_with_error` as the race-condition backstop; this is the legible
  #     check that explains it.
  #   * no memberships, not even ended ones. Deleting would cascade through
  #     `organisation_memberships` and erase the record of who belonged to the club
  #     and when they left — which is exactly the history that makes an old
  #     assessment explicable. A genuine club is therefore never deletable; only
  #     an empty mistake is.
  def deletable?
    child_organisations.none? && organisation_memberships.none?
  end

  def deletable_blocker
    return "It still has child organisations" if child_organisations.exists?
    return "It still has members" if organisation_memberships.exists?

    nil
  end

  # --- serialization helpers -------------------------------------------------

  # The per-record path, used when the caller supplied neither a precomputed set nor
  # the "oversight can edit everything" flag — a single `show`, for instance.
  def default_can_edit?
    editable_by?(Current&.user&.person) || oversight?
  end

  # `editable_all` is a flag rather than a sentinel value inside `editable_ids`
  # because "no ids" and "every id" are opposite answers, and conflating the two is
  # what sent admins down this per-record path and made a list cost a query per row.
  def can_edit_flag(editable_ids, editable_all)
    return true if editable_all
    return default_can_edit? if editable_ids.nil?

    editable_ids.include?(id)
  end

  def deletable_with_counts?(child_counts, membership_counts)
    children = child_counts ? child_counts.fetch(id, 0) : child_organisations.count
    members = membership_counts ? membership_counts.fetch(id, 0) : organisation_memberships.count

    children.zero? && members.zero?
  end

  def depth
    ancestors.size
  end

  # Every ancestor, nearest first.
  #
  # The walk is a recursive CTE carrying a `depth` column, because a CTE's row
  # order is not guaranteed by SQL: without an explicit depth there is no way to
  # ask for "nearest first", and a caller walking up the tree needs the immediate
  # parent first.
  #
  # Assembled from the ordered ids rather than ordered in SQL, so the traversal
  # order the query already computed is preserved exactly. One extra query, and
  # organisation trees are small enough that it is not worth a CASE expression.
  def ancestors
    in_traversal_order(ancestor_ids)
  end

  # Every descendant, nearest first. Same walk, downward.
  def descendants
    in_traversal_order(descendant_ids)
  end

  # The ids of every ancestor, nearest first. The recursive step joins
  # `o.id = tree.parent_id`, which walks *up* the tree one parent at a time.
  def ancestor_ids
    self.class.connection.select_values(<<~SQL.squish)
      WITH RECURSIVE tree(id, parent_id, depth) AS (
        SELECT id, parent_organisation_id, 0 FROM organisations WHERE id = #{id}
        UNION ALL
        SELECT o.id, o.parent_organisation_id, tree.depth + 1
        FROM organisations o
        JOIN tree ON o.id = tree.parent_id
      )
      SELECT id FROM tree WHERE id <> #{id} ORDER BY depth
    SQL
  end

  # The ids of every descendant, nearest first. Note the join runs the other way
  # round — `o.parent_organisation_id = tree.id` — because the walk goes *down* to
  # the children. Joining on the id instead would silently re-walk the ancestors
  # and return nothing for a root.
  def descendant_ids
    self.class.connection.select_values(<<~SQL.squish)
      WITH RECURSIVE tree(id, parent_id, depth) AS (
        SELECT id, parent_organisation_id, 0 FROM organisations WHERE id = #{id}
        UNION ALL
        SELECT o.id, o.parent_organisation_id, tree.depth + 1
        FROM organisations o
        JOIN tree ON o.parent_organisation_id = tree.id
      )
      SELECT id FROM tree WHERE id <> #{id} ORDER BY depth
    SQL
  end

  def root
    root? ? self : self.class.find_by(id: ancestor_ids.last)
  end

  def logo_attached?
    logo.attached?
  end

  # An absolute URL for the logo, or nil. Host and protocol are supplied by the
  # controller because a JSON payload cannot use the view helper `url_for` that the
  # server-rendered equivalent relies on.
  #
  # Both are needed and both were wrong once: `request.host` omits the port, and
  # `rails_blob_url` otherwise falls back to the app's default protocol. That
  # produced `http://127.0.0.1/...` for a service actually listening on
  # `https://127.0.0.1:3001`, so every stored logo failed to load. The host is
  # `host_with_port` for the same reason — a portless URL points at :80.
  def logo_url(host = nil, protocol = nil)
    return nil unless logo.attached?

    options = { host: host || "localhost:3000" }
    options[:protocol] = protocol if protocol.present?
    Rails.application.routes.url_helpers.rails_blob_url(logo, **options)
  end

  # The permission and count arguments are all optional and are supplied in bulk
  # when a whole page is rendered. Each one can be derived from this record alone,
  # but doing so costs a query per row, so the controller hoists them into grouped
  # queries and passes them in. A single `show` passes none and pays the two or
  # three queries, which is the right trade at that size.
  def metadata(host: nil, protocol: nil, editable_ids: nil, editable_all: false,
               child_counts: nil, membership_counts: nil)
    {
      id: id,
      name: name,
      slug: slug,
      description: description,
      acronym: acronym,
      organisation_type: organisation_type,
      status: status,
      status_label: status_label,
      parent_organisation_id: parent_organisation_id,
      parent_organisation: parent_organisation && {
        id: parent_organisation.id,
        name: parent_organisation.name
      },
      child_count: child_counts ? child_counts.fetch(id, 0) : child_organisations.count,
      depth: depth,
      # The upload ceiling is published with the record so a client can refuse a
      # file before sending it, rather than after a rejected round trip.
      logo_url: logo_url(host, protocol),
      logo_attached: logo_attached?,
      # Whether the caller may change this record. Published per row because the
      # answer differs by organisation: a curator can edit all of them, a club's
      # owner only their own, and the SPA cannot infer that from a role alone.
      can_edit: can_edit_flag(editable_ids, editable_all),
      can_delete: deletable_with_counts?(child_counts, membership_counts),
      created_by_person: created_by_person && {
        id: created_by_person.id,
        name: created_by_person.full_name
      },
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  # Mirrors `ContentAuthorization#oversight?`. Repeated rather than shared because a
  # model must not depend on a controller concern; both are two lines and the test
  # that checks `can_edit` for a curator pins them together.
  def oversight?
    user = Current&.user
    user.present? && (user.admin? || user.curator?)
  end

  # Loads the given ids into records while preserving the order the query
  # returned them in — which `where(id: ...)` on its own would not.
  def in_traversal_order(ids)
    return [] if ids.empty?

    by_id = self.class.where(id: ids).index_by(&:id)
    ids.filter_map { |organisation_id| by_id[organisation_id] }
  end

  # Logo content type, size and — unlike the reference implementation, which
  # declares MAX_LOGO_DIMENSION but never checks it — actual pixel dimensions.
  def logo_content_type_size_and_dimensions
    blob = logo.blob

    unless ALLOWED_LOGO_TYPES.include?(blob.content_type)
      errors.add(:logo, "must be an image (PNG, JPEG, GIF, WEBP or SVG)")
    end

    if blob.byte_size > MAX_LOGO_SIZE
      errors.add(:logo, "must be smaller than #{MAX_LOGO_SIZE / 1.megabyte} MB")
    end

    oversized_dimension(blob)&.then do |dimension|
      errors.add(:logo, "must be no larger than #{MAX_LOGO_DIMENSION}px on its longest side")
    end
  end

  # Returns a human label for the offending side ("width"/"height"), or nil when
  # the image is fine or cannot be measured. An SVG has no intrinsic pixel size
  # and is always allowed — it is vector, so it cannot blow up a layout.
  def oversized_dimension(blob)
    return nil if blob.content_type == "image/svg+xml"

    metadata = blob.metadata
    return nil unless metadata.is_a?(Hash) && metadata["identified"]

    width = metadata["width"].to_i
    height = metadata["height"].to_i
    return nil if width.zero? && height.zero?

    return "width" if width > MAX_LOGO_DIMENSION
    return "height" if height > MAX_LOGO_DIMENSION

    nil
  end

  def parent_must_not_be_self
    return if parent_organisation_id.blank?
    return unless persisted? && parent_organisation_id == id

    errors.add(:parent_organisation, "cannot be the organisation itself")
  end

  # Making a descendant one's parent would build a loop — A → B → C → A — which
  # no longer has a root and makes every walk above run forever. A self-parent is
  # the trivial case and is reported separately, because "cannot be itself" says
  # more to a coach than "would create a cycle".
  def parent_must_not_create_a_cycle
    return if parent_organisation_id.blank? || new_record?
    return unless persisted?

    candidate = Organisation.find_by(id: parent_organisation_id)
    # An unknown parent is the association's error to report, not a cycle.
    return if candidate.nil?
    # If this organisation is already somewhere above the proposed parent, then
    # making that parent point back here would close the loop. Anything else is a
    # legitimate re-parenting.
    return unless candidate.ancestor_ids.include?(id)

    errors.add(
      :parent_organisation,
      "cannot be a descendant of this organisation, as that would create a cycle"
    )
  end
end
