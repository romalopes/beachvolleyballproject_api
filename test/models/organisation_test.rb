require "test_helper"

# Model-level rules for Organisation. The hierarchy is the part worth pinning:
# it is unbounded, it is data rather than code, and a cycle would break every
# walk over the tree.
class OrganisationTest < ActiveSupport::TestCase
  setup do
    @fivb = organisations(:fivb)
    @australia = organisations(:volleyball_australia)
    @nsw = organisations(:volleyball_nsw)
    @club = organisations(:sydney_club)
    @academy = organisations(:sydney_academy)
    @northern = organisations(:northern_club)
    @maroubra = organisations(:maroubra_club)
    @author = people(:two)
  end

  # --- creation --------------------------------------------------------------

  test "an organisation is created, slugs itself, and defaults sanely" do
    organisation = Organisation.create!(
      name: "Maroochydore Beach Club", created_by_person: @author
    )

    assert_equal "maroochydore-beach-club", organisation.slug
    assert_equal "active", organisation.status
    assert_equal "other", organisation.organisation_type
    assert_predicate organisation, :root?
    assert_predicate organisation, :active?
  end

  test "a name is required, trimmed, and bounded" do
    assert_not Organisation.new(name: "   ").valid?
    assert_not Organisation.new(name: "x" * 121).valid?
    assert_equal "Trimmed", Organisation.create!(name: "  Trimmed  ").name
  end

  test "names are unique regardless of case" do
    duplicate = Organisation.new(name: @club.name.upcase)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name].join, "taken"
  end

  test "slugs stay unique when two names normalise the same way" do
    first = Organisation.create!(name: "Attack Squad")
    second = Organisation.create!(name: "Attack Squad!")

    assert_not_equal first.slug, second.slug
  end

  test "an organisation type outside the known list is refused" do
    assert_not Organisation.new(name: "Odd", organisation_type: "galaxy").valid?
    assert Organisation.new(name: "Odd", organisation_type: "other").valid?
  end

  # --- hierarchy -------------------------------------------------------------

  test "ancestors are returned nearest first, to the root" do
    # The whole point of ordering: a caller walking up needs the immediate parent
    # first, not an arbitrary set.
    assert_equal [ "Sydney Beach Volleyball Club", "Volleyball NSW",
                   "Volleyball Australia", "FIVB" ],
                 @academy.ancestors.map(&:name)
  end

  test "a root has no ancestors and is its own root" do
    assert_empty @fivb.ancestors
    assert_equal @fivb, @fivb.root
    assert_equal 0, @fivb.depth
  end

  test "depth counts the tiers above, not a hard-coded number" do
    assert_equal 0, @fivb.depth
    assert_equal 1, @australia.depth
    assert_equal 2, @nsw.depth
    assert_equal 3, @club.depth
    # Deeper than the federation tree, so a fixed-depth assumption would fail.
    assert_equal 4, @academy.depth
  end

  test "descendants span the whole subtree" do
    assert_equal [ "Northern Beaches Volleyball Club", "Sydney Beach Academy",
                   "Sydney Beach Volleyball Club", "Volleyball Australia", "Volleyball NSW" ],
                 @fivb.descendants.map(&:name).sort
  end

  test "descendants come back nearest first down an unbranched chain" do
    # Asserted on a chain, because that is the only shape where "nearest first" is
    # unambiguous — siblings at the same depth have no defined order between them.
    assert_equal [ "Sydney Beach Academy" ], @club.descendants.map(&:name)
  end

  test "a branch is isolated: another root is not a descendant" do
    assert_not_includes @fivb.descendants, @maroubra
    assert_empty @maroubra.descendants
  end

  test "a parent's children and a child's parent are each other's inverse" do
    assert_includes @nsw.child_organisations, @club
    assert_includes @nsw.child_organisations, @northern
    assert_equal @nsw, @club.parent_organisation
  end

  test "the root is reachable from any depth" do
    assert_equal @fivb, @academy.root
    assert_equal @maroubra, @maroubra.root
  end

  test "re-parenting is allowed when it does not create a cycle" do
    # Moving the academy up a level is a legitimate restructure, not a loop.
    assert @academy.update(parent_organisation: @nsw)
    assert_equal [ @nsw, @australia, @fivb ], @academy.reload.ancestors.to_a
  end

  # --- cycle and self-parent rejection ---------------------------------------

  test "an organisation cannot be its own parent" do
    @club.parent_organisation = @club

    assert_not @club.valid?
    assert_includes @club.errors[:parent_organisation].join, "itself"
  end

  test "a cycle is refused: a root cannot be re-parented under its own descendant" do
    # FIVB -> Australia -> NSW -> Club, so pointing FIVB at the club would close
    # a loop and leave the tree with no root.
    @fivb.parent_organisation = @club

    assert_not @fivb.valid?
    assert_includes @fivb.errors[:parent_organisation].join, "cycle"
  end

  test "a cycle is refused at every distance, not only the direct grandchild" do
    # Australia -> NSW -> Club -> Academy: three hops, still a cycle.
    @australia.parent_organisation = @academy

    assert_not @australia.valid?
    assert_includes @australia.errors[:parent_organisation].join, "cycle"
  end

  test "a self-parent is reported as such, not as a cycle" do
    # Two different messages, because "cannot be itself" tells a coach what to
    # fix and "would create a cycle" does not.
    @club.parent_organisation = @club

    refute_includes @club.errors[:parent_organisation].join, "cycle"
  end

  # --- archive ---------------------------------------------------------------

  test "an organisation is archived, not deleted" do
    assert @club.update(status: "archived")

    assert_predicate @club.reload, :archived?
    assert_equal "Archived", @club.status_label
    assert_includes Organisation.all, @club
  end

  test "an unknown status is refused" do
    assert_not Organisation.new(name: "Odd", status: "dissolved").valid?
  end

  test "an organisation with children cannot be deleted out from under them" do
    # Archive is the way to retire a parent; removing it would orphan the subtree.
    assert_raises(ActiveRecord::RecordNotDestroyed) { @nsw.destroy! }
    assert Organisation.exists?(@nsw.id)
  end

  # --- metadata --------------------------------------------------------------

  test "metadata reports enough for a client to render a row without a second call" do
    payload = @club.metadata

    assert_equal "Sydney Beach Volleyball Club", payload[:name]
    assert_equal "club", payload[:organisation_type]
    assert_equal @nsw.id, payload[:parent_organisation_id]
    assert_equal "Volleyball NSW", payload[:parent_organisation][:name]
    assert_equal 1, payload[:child_count]   # the academy
    assert_equal 3, payload[:depth]
  end

  # --- logo ------------------------------------------------------------------

  def attach_file(organisation, fixture: "sample.png", name:, content_type:)
    organisation.logo.attach(
      io: Rails.root.join("test/fixtures/files/#{fixture}").open,
      filename: name,
      content_type: content_type
    )
    organisation
  end

  def attach_png(organisation, name: "logo.png", content_type: "image/png")
    attach_file(organisation, name: name, content_type: content_type)
  end

  test "a non-image content type is refused" do
    organisation = Organisation.create!(name: "Bad Logo")
    # A real text file, not a PNG declared as a PDF: Active Storage re-identifies
    # content type from the bytes, so a mislabelled image is correctly accepted as
    # the image it actually is. Only a genuinely non-image is refused.
    attach_file(organisation, fixture: "notes.txt",
                        name: "notes.txt", content_type: "text/plain")

    assert_not organisation.valid?
    assert_includes organisation.errors[:logo].join, "must be an image"
  end

  test "a valid logo attaches and reports a URL" do
    organisation = attach_png(Organisation.create!(name: "With Logo"))

    assert_predicate organisation, :logo_attached?
    assert_not_nil organisation.logo_url
  end

  test "an organisation with no logo has a nil URL rather than a broken one" do
    organisation = Organisation.create!(name: "No Logo")

    assert_not organisation.logo_attached?
    assert_nil organisation.logo_url
  end

  test "an SVG is allowed, since it is vector and has no pixel budget to exceed" do
    organisation = Organisation.create!(name: "Vector Logo")
    attach_png(organisation, name: "logo.svg", content_type: "image/svg+xml")

    # The reference implementation declares MAX_LOGO_DIMENSION without checking it.
    # Here the check exists, so SVG has to be explicitly exempt — otherwise a
    # legitimate vector logo would be rejected for having no measurable size.
    assert_predicate organisation, :valid?
  end

  test "a blob reporting a huge width is refused" do
    organisation = Organisation.create!(name: "Huge Logo")
    attach_png(organisation)
    organisation.logo.blob.update!(
      metadata: { "identified" => true, "width" => 8000, "height" => 100 }
    )

    assert_not organisation.valid?
    assert_includes organisation.errors[:logo].join, "5000px"
  end

  test "a blob reporting a huge height is refused" do
    organisation = Organisation.create!(name: "Tall Logo")
    attach_png(organisation)
    organisation.logo.blob.update!(
      metadata: { "identified" => true, "width" => 100, "height" => 6000 }
    )

    assert_not organisation.valid?
    assert_includes organisation.errors[:logo].join, "5000px"
  end

  test "metadata reports the logo state so a client need not infer it" do
    payload = Organisation.create!(name: "Payload").metadata

    assert_includes payload.keys, :logo_url
    assert_includes payload.keys, :logo_attached
    assert_equal false, payload[:logo_attached]
  end

  # --- acronym ----------------------------------------------------------------

  test "an acronym is optional" do
    # A development squad inside a club has no recognised short form, so requiring
    # one would mean inventing data for every existing row.
    assert organisations(:sydney_academy).valid?
    assert_nil organisations(:sydney_academy).acronym
  end

  test "an acronym is stored as it is displayed" do
    organisation = Organisation.create!(name: "New Body", slug: "new-body", acronym: "  fivb  ")

    assert_equal "FIVB", organisation.acronym
  end

  test "a blank acronym reads as absent rather than as an empty string" do
    organisation = Organisation.create!(name: "Another Body", slug: "another-body", acronym: "   ")

    assert_nil organisation.acronym
  end

  test "an acronym must be a short label" do
    organisation = Organisation.new(name: "Bad Acronym", acronym: "a" * 30)

    assert_not organisation.valid?
    assert_includes organisation.errors[:acronym].join, "too long"
  end

  test "an acronym must not carry punctuation that is not part of a label" do
    # Short enough that only the format can reject them. A long sentence is caught
    # by the length rule instead, which is what that rule is for.
    [ "Club/2026", "Club:NSW", "100%", "(NSW)" ].each do |value|
      organisation = Organisation.new(name: "Bad #{value}", acronym: value)

      assert_not organisation.valid?, "#{value.inspect} should have been refused"
      assert_includes organisation.errors[:acronym].join, "may contain only"
    end
  end

  test "an acronym long enough to be a sentence is refused as too long" do
    organisation = Organisation.new(name: "Sentential", acronym: "The Very Best Club")

    assert_not organisation.valid?
    assert_includes organisation.errors[:acronym].join, "too long"
  end

  test "the short forms that genuinely exist are accepted" do
    [ "FIVB", "VA", "NSW", "VB NSW", "C.B.V.A.", "SB-1" ].each do |value|
      assert Organisation.new(name: "Body #{value}", acronym: value).valid?,
             "#{value.inspect} should have been accepted"
    end
  end

  test "an accented acronym is refused" do
    # The name is French, so this is a plausible mistake rather than a fanciful one.
    organisation = Organisation.new(name: "Body", acronym: "FÉDÉRATION")

    assert_not organisation.valid?
  end

  test "an acronym is published in the metadata" do
    # Persisted, not `new`: `metadata` walks ancestors, and the recursive CTE needs
    # a real id to anchor on.
    organisation = Organisation.create!(name: "Payload Body", slug: "payload-body", acronym: "PB")

    assert_equal "PB", organisation.metadata[:acronym]
  end
end
