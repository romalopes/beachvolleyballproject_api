require "test_helper"

# Model rules for OrganisationMembership.
#
# The two facts under test are the ones a bug would be quiet about: that membership
# is keyed on Person rather than on an account or a profile, and that it has a
# lifecycle rather than being deleted. Everything else follows from those.
class OrganisationMembershipTest < ActiveSupport::TestCase
  setup do
    @club = organisations(:sydney_club)
    @nsw = organisations(:volleyball_nsw)
    @academy = organisations(:sydney_academy)
    @owner = people(:two)
    @officer = people(:club_officer)
    @coach = people(:club_coach)
    @accountless = people(:accountless_player)
  end

  def membership(overrides = {})
    OrganisationMembership.create!(
      { organisation: @club, person: people(:merged), role: "member", status: "active" }
        .merge(overrides)
    )
  end

  # Unsaved, for rules that are about *validation*. `create!` would raise before the
  # assertion could be made.
  def built_membership(overrides = {})
    OrganisationMembership.new(
      { organisation: @club, person: people(:merged), role: "member", status: "active" }
        .merge(overrides)
    )
  end

  # --- identity --------------------------------------------------------------

  test "membership is keyed on Person, so an accountless person can belong" do
    row = organisation_memberships(:accountless_club_member)

    assert_equal @accountless.id, row.person_id
    # The whole point: no Account is required, and no profile either.
    assert_nil @accountless.account
    assert_predicate row, :active?
  end

  test "a person may belong to several organisations at once" do
    person = people(:merged)
    membership(organisation: @club, person: person)
    membership(organisation: @nsw, person: person)

    assert_equal 2, person.organisation_memberships.count
    assert_includes person.active_organisation_ids, @club.id
    assert_includes person.active_organisation_ids, @nsw.id
  end

  test "a person cannot be a member of the same organisation twice" do
    membership(person: people(:merged))

    duplicate = OrganisationMembership.new(organisation: @club, person: people(:merged))

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:person_id].join, "already a member"
  end

  # --- roles -----------------------------------------------------------------

  test "only a known role is accepted" do
    assert_not built_membership(role: "supreme_leader").valid?
    assert built_membership(role: "coach").valid?
  end

  test "manages? covers the roles that can run a roster and nothing else" do
    # Built rather than created: the Sydney club already has a fixture owner, and
    # this is about the predicate, not about saving.
    assert built_membership(role: "owner").manages?
    assert built_membership(role: "administrator").manages?
    # A coach coaches. That is not a grant over who belongs to the club.
    assert_not built_membership(role: "coach").manages?
    assert_not built_membership(role: "member").manages?
  end

  # --- single owner ----------------------------------------------------------

  test "an organisation may have only one active owner" do
    rival = built_membership(role: "owner")

    assert_not rival.valid?
    assert_includes rival.errors[:role].join, "already has an active owner"
  end

  test "the database refuses a second active owner even when the model check is bypassed" do
    # The Sydney club already has a fixture owner, so this is only about the index.
    second = OrganisationMembership.new(organisation: @club, person: people(:merged),
                                        role: "owner", status: "active")

    # The model validation can lose a race; the partial unique index cannot.
    assert_raises(ActiveRecord::RecordNotUnique) { second.save(validate: false) }
  end

  test "a second owner is allowed once the first has ended" do
    organisation_memberships(:owner_of_sydney_club).end!

    assert membership(role: "owner").valid?
  end

  test "an organisation's owner is read from the membership, not from its creator" do
    # The two must never disagree: that is how a transferred club ends up with
    # nobody able to run it.
    assert_equal @owner, @club.owner
    assert @club.owner?(@owner)
    assert_not @club.owner?(@officer)
  end

  # --- lifecycle -------------------------------------------------------------

  test "becoming active stamps joined_at" do
    row = membership(status: "pending")
    assert_nil row.joined_at

    row.activate!

    assert_equal "active", row.status
    assert_not_nil row.joined_at
  end

  test "a pending membership is not active and grants nothing" do
    row = organisation_memberships(:pending_academy_member)

    assert_equal "pending", row.status
    assert_not row.active?
    assert_not_includes @academy.members.reload.map(&:id), row.person_id
  end

  test "a suspended membership is not active" do
    row = organisation_memberships(:suspended_nsw_coach)

    assert_not row.active?
    assert_not_includes @coach.active_organisation_ids, @nsw.id
  end

  test "ending stamps left_at and keeps the record" do
    row = organisation_memberships(:club_player)
    row.end!

    assert_equal "ended", row.status
    assert_not_nil row.left_at
    # Not deleted. A historical assessment must still be explicable by the
    # membership that existed when it was recorded.
    assert OrganisationMembership.exists?(row.id)
    assert_not_includes @club.members.reload.map(&:id), row.person_id
  end

  test "an ended membership is stamped rather than stored inconsistent" do
    row = membership(status: "ended", left_at: nil)

    # The model fills `left_at` in, so the two can never disagree. The database
    # check is the backstop for a direct write that bypasses this.
    assert_predicate row, :valid?
    assert_predicate row, :ended?
    assert_not_nil row.left_at
  end

  test "re-activating an ended membership reuses the row rather than adding another" do
    row = organisation_memberships(:club_player)
    row.end!
    row.activate!

    assert_equal 1, @club.organisation_memberships.where(person_id: row.person_id).count
    assert_predicate row, :active?
  end

  # --- the visibility rule ---------------------------------------------------

  test "two members of the same club are peers" do
    # The §15 requirement: club-level visibility without a PlayerCoach row.
    assert @owner.shares_organisation_with?(@officer)
  end

  test "membership in a parent organisation grants nothing about a club" do
    # §2.4. The national official is in Volleyball Australia; the owner is in the
    # Sydney club. Sitting above a club in the tree is not a licence to see it.
    refute people(:national_official).shares_organisation_with?(@owner)
  end

  test "membership in a different club grants nothing" do
    northern = organisations(:northern_club)
    other = OrganisationMembership.create!(organisation: northern, person: people(:merged),
                                          role: "member", status: "active")

    refute people(:merged).shares_organisation_with?(@owner)
    assert other.active?
  end

  test "a former member shares nothing, because their membership has ended" do
    # A person whose only membership was with the Northern club, and a current
    # member of that same club. Nothing else links them, so the ended row is the
    # only thing the test could be passing on.
    leaver = people(:merged)
    stale = OrganisationMembership.create!(organisation: organisations(:northern_club),
                                          person: leaver, role: "member", status: "active")
    leaver.active_organisation_ids
    stale.end!

    assert_predicate stale, :ended?
    assert_empty organisations(:northern_club).members.reload.map(&:id)
    # The Northern club can no longer see them...
    refute leaver.shares_organisation_with?(people(:club_officer).tap do |officer|
      officer.organisation_memberships.create!(organisation: organisations(:northern_club),
                                              role: "member", status: "active")
    end)
  end

  test "managing an organisation is the owner's and administrators' privilege" do
    assert @club.manageable_by?(@owner)
    assert @club.manageable_by?(@officer)
    # Being on the roster is not authority over it.
    assert_not @club.manageable_by?(@accountless)
    assert_not @club.manageable_by?(nil)
  end

  # --- §15: player visibility through membership ------------------------------
  #
  # The point of recording a roster at all: a club's players become visible to the
  # club's own people, without anyone having to restate that as a list of
  # coach-to-player grants that would then drift out of date.

  test "organisation peers are each other's peers" do
    assert_includes @owner.organisation_peer_ids, @officer.id
    assert_includes @officer.organisation_peer_ids, @owner.id
  end

  test "a national official is nobody's peer, despite sitting above the club" do
    # The hierarchy is not a grant. If this ever passed because of the tree rather
    # than a shared club, the whole access model would be wrong.
    assert_not_includes @owner.organisation_peer_ids, people(:national_official).id
  end

  test "a private player of one's own club becomes visible" do
    viewer = users(:six)   # Maria Silva, owner of the Sydney club
    player = player_profiles(:private_club_player)

    # The profile is private, so nothing but the shared club membership can explain
    # this being visible at all.
    assert_equal "private", player.visibility
    assert player.visible_to_user?(viewer)
    assert_includes PlayerProfile.visible_to(viewer), player
  end

  test "ending a membership withdraws the visibility it granted" do
    viewer = users(:six)
    player = player_profiles(:private_club_player)
    assert player.visible_to_user?(viewer)

    # The officer's membership ends, so the club route to this player closes.
    OrganisationMembership.find_by(organisation: @club, person_id: @officer.id).end!

    assert_not player.reload.visible_to_user?(viewer)
  end

  test "the list and the single record agree about who may see a player" do
    # Two implementations of one rule: a scope and an instance method. If they ever
    # drift, a list can show an item that the item itself then refuses.
    viewer = users(:six)
    PlayerProfile.where.not(person_id: nil).find_each do |profile|
      in_list = PlayerProfile.visible_to(viewer).include?(profile)
      assert_equal in_list, profile.visible_to_user?(viewer),
                   "visible_to and visible_to_user? disagree for #{profile.id}"
    end
  end
end
