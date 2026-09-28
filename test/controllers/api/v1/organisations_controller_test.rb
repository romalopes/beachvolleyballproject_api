require "test_helper"

# Request tests for the Organisations API.
#
# Two things are pinned here: the hierarchy survives the round trip, and managing
# the tree is genuinely admin-only. The read is deliberately open — the tree is
# shared context — so a coach may look up a club without being able to rename it
# or re-parent it.
class Api::V1::OrganisationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)
    @curator = users(:four)   # oversight, but not an admin
    @coach = users(:six)
    @player_user = users(:one)

    @fivb = organisations(:fivb)
    @australia = organisations(:volleyball_australia)
    @nsw = organisations(:volleyball_nsw)
    @club = organisations(:sydney_club)
  end

  def json
    JSON.parse(response.body)
  end

  def post_json(path, payload)
    post path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  def patch_json(path, payload)
    patch path, params: payload.to_json, headers: { "Content-Type" => "application/json" }
  end

  # --- read ------------------------------------------------------------------

  test "index requires authentication" do
    get "/api/v1/organisations"
    assert_response :unauthorized
  end

  test "index is readable by a training manager, as the other catalogues are" do
    # The same gate as groups and players: a coach can look up a club without being
    # able to rename it or re-parent it.
    sign_in_as(@coach)
    get "/api/v1/organisations"

    assert_response :success
    assert json["data"].any? { |row| row["name"] == "Sydney Beach Volleyball Club" }
  end

  test "index filters by status and by type" do
    sign_in_as(@coach)
    get "/api/v1/organisations", params: { organisation_type: "club" }

    assert_response :success
    names = json["data"].map { |row| row["name"] }
    assert_includes names, "Sydney Beach Volleyball Club"
    assert_not_includes names, "FIVB"

    get "/api/v1/organisations", params: { status: "archived" }
    assert_response :success
    assert_equal [ "Retired Surfing Association" ], json["data"].map { |row| row["name"] }
  end

  test "show reports the parent and depth without a second call" do
    sign_in_as(@coach)
    get "/api/v1/organisations/#{@club.id}"

    assert_response :success
    body = json
    assert_equal "Sydney Beach Volleyball Club", body["name"]
    assert_equal "club", body["organisation_type"]
    assert_equal "Volleyball NSW", body["parent_organisation"]["name"]
    assert_equal 3, body["depth"]
    assert_equal 1, body["child_count"]
  end

  test "an unknown id is a 404, not an empty record" do
    sign_in_as(@coach)
    get "/api/v1/organisations/999_999"

    assert_response :not_found
  end

  # --- create ----------------------------------------------------------------

  test "an admin creates a child organisation" do
    sign_in_as(@admin)
    assert_difference -> { Organisation.count }, 1 do
      post_json "/api/v1/organisations", organisation: {
        name: "Manly Beach Volleyball Club",
        organisation_type: "club",
        parent_organisation_id: @nsw.id
      }
    end

    assert_response :created
    body = json
    assert_equal "manly-beach-volleyball-club", body["slug"]
    assert_equal @nsw.id, body["parent_organisation_id"]
    assert_equal 3, body["depth"]
  end

  test "creating a root organisation is allowed" do
    sign_in_as(@admin)
    post_json "/api/v1/organisations", organisation: {
      name: "Standalone Academy", organisation_type: "academy"
    }

    assert_response :created
    assert_equal 0, json["depth"]
    assert_nil json["parent_organisation_id"]
  end

  test "a re-parent that would close a cycle is refused, and writes nothing" do
    sign_in_as(@admin)

    # Volleyball NSW sits under Volleyball Australia, so pointing Australia at NSW
    # would make the tree loop.
    assert_no_difference -> { Organisation.count } do
      patch_json "/api/v1/organisations/#{@australia.id}", organisation: {
        parent_organisation_id: @nsw.id
      }
    end

    assert_response :unprocessable_entity
    assert_match(/cycle/, json["errors"].join(" "))
  end

  test "a self-parent is refused with a message that says so" do
    sign_in_as(@admin)
    patch_json "/api/v1/organisations/#{@nsw.id}", organisation: {
      parent_organisation_id: @nsw.id
    }

    assert_response :unprocessable_entity
    assert_match(/itself/, json["errors"].join(" "))
  end

  test "an unknown organisation type is refused" do
    sign_in_as(@admin)
    post_json "/api/v1/organisations", organisation: {
      name: "Odd Body", organisation_type: "galaxy"
    }

    assert_response :unprocessable_entity
  end

  # --- archive / restore -----------------------------------------------------

  test "an admin archives an organisation without touching its children" do
    sign_in_as(@admin)
    post "/api/v1/organisations/#{@club.id}/archive"

    assert_response :success
    assert_equal "archived", json["status"]
    # The academy below it is untouched: archiving a parent must not detach
    # what sits under it.
    assert_equal "active", organisations(:sydney_academy).reload.status
  end

  test "archiving twice is refused" do
    sign_in_as(@admin)
    @club.update!(status: "archived")

    post "/api/v1/organisations/#{@club.id}/archive"

    assert_response :unprocessable_entity
    assert_match(/already archived/, json["errors"].join(" "))
  end

  test "an admin restores an archived organisation" do
    sign_in_as(@admin)
    post "/api/v1/organisations/#{organisations(:retired_association).id}/restore"

    assert_response :success
    assert_equal "active", json["status"]
  end

  test "restoring one that is not archived is refused" do
    sign_in_as(@admin)
    post "/api/v1/organisations/#{@club.id}/restore"

    assert_response :unprocessable_entity
    assert_match(/not archived/, json["errors"].join(" "))
  end

  test "there is no delete route at all" do
    sign_in_as(@admin)
    delete "/api/v1/organisations/#{@club.id}"

    # Archive is the only retirement there is; a parent with children could not
    # safely be removed even if a route existed.
    assert_response :not_found
  end

  # --- logo ------------------------------------------------------------------
  #
  # The first file upload this API accepts, so the transport is under test as well
  # as the rules: multipart in, an absolute URL back out.

  def png_upload(filename: "logo.png", content_type: "image/png")
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/sample.png"),
      content_type,
      original_filename: filename
    )
  end

  test "an admin attaches a logo and gets an absolute URL back" do
    sign_in_as(@admin)

    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }

    assert_response :success
    body = json
    assert body["logo_attached"]
    # Absolute, so the SPA can use it directly without knowing its own origin.
    assert_match %r{\Ahttps?://}, body["logo_url"]
    assert_predicate @club.reload, :logo_attached?
  end

  test "an organisation with no logo reports null rather than a broken URL" do
    sign_in_as(@coach)
    get "/api/v1/organisations/#{@club.id}"

    assert_response :success
    assert_not json["logo_attached"]
    assert_nil json["logo_url"]
  end

  test "uploading a logo replaces the previous one instead of accumulating" do
    sign_in_as(@admin)
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }
    assert_response :success

    post "/api/v1/organisations/#{@club.id}/logo",
         params: { logo: png_upload(filename: "second.png") }

    assert_response :success
    # One attachment, not two: a replacement must not leave the old blob behind.
    assert_equal 1, @club.reload.logo.attachments.count
    assert_equal 1, ActiveStorage::Attachment
                     .where(record_type: "Organisation", record_id: @club.id).count
  end

  test "a non-image is refused and leaves no attachment behind" do
    sign_in_as(@admin)

    # A genuinely non-image file rather than a PNG declared as a PDF: Active
    # Storage re-identifies content type from the bytes, so a mislabelled image is
    # correctly accepted as the image it actually is, and only real non-images are
    # refused.
    post "/api/v1/organisations/#{@club.id}/logo",
         params: {
           logo: Rack::Test::UploadedFile.new(
             Rails.root.join("test/fixtures/files/notes.txt"),
             "text/plain", original_filename: "notes.txt"
           )
         }

    assert_response :unprocessable_entity
    assert_match(/must be an image/, json["errors"].join(" "))
    assert_not @club.reload.logo_attached?
  end

  test "a missing file is refused with a message that says so" do
    sign_in_as(@admin)
    post "/api/v1/organisations/#{@club.id}/logo"

    assert_response :unprocessable_entity
    assert_match(/logo file is required/i, json["errors"].join(" "))
  end

  test "a coach may not upload a logo" do
    sign_in_as(@coach)
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }

    assert_response :forbidden
    assert_not @club.reload.logo_attached?
  end

  test "a curator may not upload a logo" do
    sign_in_as(@curator)
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }

    assert_response :forbidden
  end

  test "a guest may not upload a logo" do
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }

    assert_response :unauthorized
  end

  # --- membership ------------------------------------------------------------
  #
  # Two different authorities in one place: the organisation itself is admin-only,
  # but its *roster* is delegated to the club's own owner and administrators. Being
  # on the roster is not authority over it.
  #
  # The identities matter here, so they are named rather than reused from the
  # `@admin`/`@coach` above: `six` is Maria Silva, whose Person owns the Sydney club
  # and who is emphatically *not* a site admin, which is the only way to show the
  # delegated path works. `five` is John Smith, an ordinary member of that club.

  def post_membership(organisation, person, **overrides)
    post_json "/api/v1/organisations/#{organisation.id}/members",
              membership: { person_id: person.id, **overrides }
  end

  test "the club's owner can add a member without being a site admin" do
    owner_user = users(:six)
    assert_not owner_user.admin?, "this test only means something for a non-admin"
    sign_in_as(owner_user)

    post_membership(@club, people(:national_official), role: "member", status: "active")

    assert_response :created
    assert_equal people(:national_official).id, json["person_id"]
    assert_equal "active", json["status"]
  end

  test "an ordinary member may not change the roster" do
    sign_in_as(users(:five)) # John Smith, a plain `member` of this very club
    before_count = OrganisationMembership.count

    post_membership(@club, people(:national_official))

    assert_response :forbidden
    assert_equal before_count, OrganisationMembership.count
  end

  test "a training manager who is not an officer sees only ended memberships" do
    # The organisation itself is readable by any training manager, but the roster is
    # narrower. This curator is not on the club's membership at all and has no
    # Person, so the only rows that are theirs to see are the historical ones —
    # hiding those would erase the record this feature exists to keep.
    sign_in_as(users(:four))

    get "/api/v1/organisations/#{@club.id}/members"

    assert_response :success
    ids = json["data"].map { |row| row["person_id"] }
    assert_not_includes ids, people(:club_officer).id
    assert_empty json["data"].reject { |row| row["status"] == "ended" }
  end

  test "a player who is not a training manager may not read the roster at all" do
    # John Smith is an ordinary member of the club. Being on the roster is not what
    # opens the organisation to you.
    sign_in_as(users(:five))

    get "/api/v1/organisations/#{@club.id}/members"

    assert_response :forbidden
  end

  test "the owner sees the whole roster" do
    sign_in_as(users(:six))

    get "/api/v1/organisations/#{@club.id}/members"

    assert_response :success
    assert_includes json["data"].map { |row| row["person_id"] }, people(:club_officer).id
  end

  test "a member is added as pending unless a status is given" do
    sign_in_as(users(:six))

    post_membership(@club, people(:national_official))

    assert_response :created
    # Defaulting to pending, not active: an invitation is not a grant.
    assert_equal "pending", json["status"]
    assert_equal "member", json["role"]
  end

  test "ending a membership keeps the record and stamps left_at" do
    sign_in_as(users(:six))
    membership = organisation_memberships(:club_player)

    delete "/api/v1/organisations/#{@club.id}/members/#{membership.person_id}"

    assert_response :success
    assert_equal "ended", json["status"]
    # Not deleted — a historical assessment must still be explicable.
    assert OrganisationMembership.exists?(membership.id)
    assert_not_nil OrganisationMembership.find(membership.id).left_at
  end

  test "re-adding a former member reuses the row rather than duplicating it" do
    sign_in_as(users(:six))
    membership = organisation_memberships(:club_player)
    membership.end!
    before_count = OrganisationMembership.where(organisation: @club,
                                                person: membership.person).count

    post_membership(@club, membership.person, role: "member", status: "active")

    assert_response :created
    assert_equal "active", json["status"]
    assert_equal before_count,
                 OrganisationMembership.where(organisation: @club, person: membership.person).count
  end

  test "adding the same person twice is a conflict, not a second row" do
    sign_in_as(users(:six))
    person = people(:national_official)
    post_membership(@club, person)
    assert_response :created

    post_membership(@club, person)

    # 201 here would be a lie: nothing was created.
    assert_response :conflict
    assert_equal 1, OrganisationMembership.where(organisation: @club, person: person).count
  end

  test "an unknown person is a 404" do
    sign_in_as(users(:six))

    post_json "/api/v1/organisations/#{@club.id}/members", membership: { person_id: 0 }

    assert_response :not_found
  end

  test "an officer can change a member's role" do
    sign_in_as(users(:six))
    target = organisation_memberships(:club_player)
    assert_equal "member", target.role

    patch_json "/api/v1/organisations/#{@club.id}/members/#{target.person_id}",
               membership: { role: "coach" }

    assert_response :success
    assert_equal "coach", json["role"]
    assert_equal "coach", target.reload.role
  end

  test "a role may not be changed to one that does not exist" do
    sign_in_as(users(:six))
    target = organisation_memberships(:club_player)

    patch_json "/api/v1/organisations/#{@club.id}/members/#{target.person_id}",
               membership: { role: "supreme_leader" }

    assert_response :unprocessable_entity
    assert_equal "member", target.reload.role
  end

  test "promoting a second owner is refused, and the club keeps its one owner" do
    sign_in_as(users(:six))
    target = organisation_memberships(:club_administrator)

    patch_json "/api/v1/organisations/#{@club.id}/members/#{target.person_id}",
               membership: { role: "owner" }

    assert_response :unprocessable_entity
    # The existing owner is untouched: a failed promotion must not demote anyone.
    assert_equal people(:two), @club.reload.owner
  end

  test "a member may not change their own role" do
    sign_in_as(users(:five))
    target = organisation_memberships(:club_player)

    patch_json "/api/v1/organisations/#{@club.id}/members/#{target.person_id}",
               membership: { role: "administrator" }

    assert_response :forbidden
    assert_equal "member", target.reload.role
  end

  test "ending a membership that does not exist is a 404, not a silent success" do
    sign_in_as(users(:six))

    delete "/api/v1/organisations/#{@club.id}/members/#{people(:merged).id}"

    assert_response :not_found
  end

  test "a guest may not read the roster" do
    get "/api/v1/organisations/#{@club.id}/members"
    assert_response :unauthorized
  end

  # --- authorization ---------------------------------------------------------

  test "a coach may not create, edit, archive or restore" do
    sign_in_as(@coach)

    post_json "/api/v1/organisations", organisation: { name: "Sneaky Club" }
    assert_response :forbidden

    patch_json "/api/v1/organisations/#{@club.id}", organisation: { name: "Renamed" }
    assert_response :forbidden

    post "/api/v1/organisations/#{@club.id}/archive"
    assert_response :forbidden

    post "/api/v1/organisations/#{@club.id}/restore"
    assert_response :forbidden

    # And nothing was changed by any of it.
    assert_equal "Sydney Beach Volleyball Club", @club.reload.name
    assert_equal "active", @club.status
  end

  test "a curator may not manage organisations, being oversight but not an admin" do
    sign_in_as(@curator)

    post_json "/api/v1/organisations", organisation: { name: "Curator Club" }

    # Oversight is not administration: a club's place in the federation is a claim
    # made to other clubs, not content.
    assert_response :forbidden
  end

  test "a player-role user may not read the tree" do
    sign_in_as(@player_user)
    get "/api/v1/organisations"

    assert_response :forbidden
  end

  test "a guest may not create one" do
    post_json "/api/v1/organisations", organisation: { name: "Guest Club" }
    assert_response :unauthorized
  end
end
