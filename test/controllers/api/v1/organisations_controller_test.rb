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

  test "index returns the whole hierarchy when asked for the tree" do
    # A page boundary is meaningless for a tree: a child whose parent landed on
    # another page has nothing to be drawn under, and a client walking from the
    # roots silently drops it. `tree=1` therefore bypasses pagination. The extra
    # rows are what makes this a real assertion — without them both responses
    # would be a single page and the test would pass either way.
    sign_in_as(@coach)
    (Pagination::DEFAULT_PER_PAGE + 5).times do |index|
      Organisation.create!(name: "Perf Club #{index}", slug: "perf-club-#{index}")
    end

    get "/api/v1/organisations"
    assert_operator json["data"].size, :<=, Pagination::DEFAULT_PER_PAGE

    get "/api/v1/organisations", params: { tree: "1" }
    assert_response :success
    assert_equal Organisation.count, json["data"].size
    assert_equal 1, json["meta"]["total_pages"]
    # Every parent is resolvable within the one response, which is the whole point.
    present = json["data"].map { |row| row["id"] }
    json["data"].each do |row|
      parent_id = row["parent_organisation_id"]
      assert_includes present, parent_id if parent_id
    end
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

  test "the index does not re-check membership per row for an admin" do
    # Oversight can edit every organisation, so there is nothing to look up per row.
    # A sentinel of "no ids" instead of a distinct "all ids" answer used to send
    # admins down the per-record path, costing a query for every organisation in the
    # list. Pinned because it is invisible in the response and only shows up as
    # latency on a large tree.
    sign_in_as(@admin)
    6.times do |index|
      Organisation.create!(name: "Perf Club #{index}", slug: "perf-club-#{index}")
    end

    membership_queries = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql].to_s
      membership_queries += 1 if sql.include?("organisation_memberships") && !payload[:cached]
    end

    get "/api/v1/organisations", params: { per_page: 50 }

    assert_response :success
    # Bounded, not per-row: the count must not grow with the number of rows.
    assert_operator membership_queries, :<=, 2,
                    "index issued #{membership_queries} membership queries for 15 organisations"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  # --- delete ----------------------------------------------------------------
  #
  # A hard delete exists, but only for a mistake: admin only, and only for an
  # organisation with no children and no members. Anything real is archived.

  test "an admin may delete an empty childless organisation" do
    sign_in_as(@admin)
    stray = Organisation.create!(name: "Placeholder Club", slug: "placeholder-club")

    delete "/api/v1/organisations/#{stray.id}"

    assert_response :success
    assert_nil Organisation.find_by(id: stray.id)
  end

  test "an admin may not delete an organisation that has children" do
    sign_in_as(@admin)

    delete "/api/v1/organisations/#{@nsw.id}"

    # 409, not a silent cascade: re-parenting a branch is not something a delete
    # button should do on its own.
    assert_response :conflict
    assert Organisation.exists?(@nsw.id)
  end

  test "an admin may not delete an organisation that has members" do
    # A leaf club is still a real club. Deleting it would cascade through the
    # memberships and erase the record of who belonged to it.
    leaf = organisations(:sydney_academy)
    sign_in_as(@admin)

    delete "/api/v1/organisations/#{leaf.id}"

    assert_response :conflict
    assert Organisation.exists?(leaf.id)
    assert OrganisationMembership.exists?(organisation_id: leaf.id)
  end

  test "an ended membership still blocks deletion" do
    sign_in_as(@admin)
    leaf = organisations(:northern_club)
    assert leaf.organisation_memberships.ended.exists?,
           "the fixture must have a former member for this test to mean anything"

    delete "/api/v1/organisations/#{leaf.id}"

    assert_response :conflict
    assert Organisation.exists?(leaf.id)
  end

  test "an editor may edit but may not delete" do
    # The club's owner can correct its name and logo, but deleting is destructive
    # and stays admin-only.
    sign_in_as(users(:six))
    patch_json "/api/v1/organisations/#{@club.id}", organisation: { name: "Renamed By Owner" }
    assert_response :success

    delete "/api/v1/organisations/#{@club.id}"

    assert_response :forbidden
    assert Organisation.exists?(@club.id)
  end

  test "a curator may edit but may not delete" do
    sign_in_as(@curator)

    delete "/api/v1/organisations/#{@club.id}"

    assert_response :forbidden
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

  # A file the logo content-type rule must refuse, so the "rejected replacement"
  # path is exercised rather than assumed.
  def text_file_upload(filename: "notes.txt", content_type: "text/plain")
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/notes.txt"),
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

  test "the logo URL carries the port the request arrived on" do
    # The port must survive. `request.host` omits it, so a logo was served as
    # `http://127.0.0.1/...` for a service on `https://127.0.0.1:3001` — every
    # upload succeeded and no image ever displayed.
    #
    # `host!` is the point of this test: integration requests default to port 80,
    # where `host` and `host_with_port` are the same string, so the ordinary case
    # cannot tell the two apart and the bug survives it.
    sign_in_as(@admin)
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }
    assert_response :success

    get "/api/v1/organisations/#{@club.id}", headers: { "HOST" => "api.example.test:3001" }

    assert_includes json["logo_url"], "api.example.test:3001",
                    "the logo URL must carry the port, not just the host"
  end

  test "the logo URL follows the forwarded scheme rather than the one Rails saw" do
    # TLS is terminated upstream in production, so `request.protocol` reports `http`
    # and a URL built from it would be downgraded for every browser.
    sign_in_as(@admin)
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }
    assert_response :success

    get "/api/v1/organisations/#{@club.id}", headers: { "X-Forwarded-Proto" => "https" }

    assert_equal "https", json["logo_url"].split("//").first.split(":").first
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

  test "a coach who is not an officer may not upload a logo" do
    sign_in_as(users(:three))
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }

    assert_response :forbidden
    assert_not @club.reload.logo_attached?
  end

  test "a rejected replacement leaves the existing logo intact" do
    # The regression this pins: the action used to purge first and attach second, so
    # an oversized or non-image replacement destroyed a working crest and left the
    # club with nothing at all.
    sign_in_as(@admin)
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }
    assert_response :success
    original = @club.reload.logo.blob
    assert_not_nil original

    post "/api/v1/organisations/#{@club.id}/logo",
         params: { logo: text_file_upload(filename: "notes.txt") }

    assert_response :unprocessable_entity
    # The old logo survived, and still points at the same file.
    assert @club.reload.logo_attached?
    assert_equal original.id, @club.logo.blob.id
    assert ActiveStorage::Blob.exists?(original.id)
  end

  test "a rejected first upload leaves the organisation with no logo" do
    # The mirror image: nothing to preserve, so nothing is created either.
    sign_in_as(@admin)

    post "/api/v1/organisations/#{@club.id}/logo",
         params: { logo: text_file_upload(filename: "notes.txt") }

    assert_response :unprocessable_entity
    assert_not @club.reload.logo_attached?
  end

  test "a successful replacement purges the blob it replaced" do
    sign_in_as(@admin)
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }
    original = @club.reload.logo.blob

    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload(filename: "second.png") }

    assert_response :success
    # Purged only *after* the new one was accepted, so no orphaned file is left.
    assert_not ActiveStorage::Blob.exists?(original.id)
  end

  test "a curator may upload a logo" do
    # Oversight is enough to maintain a record. This is a deliberate reversal of the
    # earlier admin-only rule: the logo is the club's own crest, not a claim made to
    # other clubs the way its place in the tree is.
    sign_in_as(@curator)
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }

    assert_response :success
    assert @club.reload.logo_attached?
  end

  test "a guest may not upload a logo" do
    post "/api/v1/organisations/#{@club.id}/logo", params: { logo: png_upload }

    assert_response :unauthorized
  end

  test "a curator may not re-parent an organisation" do
    # Re-parenting asserts this node's place to every other club, so it stayed
    # admin-only by design. Relaxing `update` to include curators, owners and the
    # creator silently relaxed *this* too, which let a club move a federation node.
    sign_in_as(@curator)
    original_parent = @australia.parent_organisation_id

    patch_json "/api/v1/organisations/#{@australia.id}",
               organisation: { parent_organisation_id: @nsw.id }

    assert_response :success
    # The rename is applied; the move is quietly dropped rather than accepted.
    assert_equal original_parent, @australia.reload.parent_organisation_id
  end

  test "the club's owner may not re-parent their own club either" do
    sign_in_as(users(:six))
    original_parent = @club.parent_organisation_id

    patch_json "/api/v1/organisations/#{@club.id}",
               organisation: { parent_organisation_id: @australia.id }

    assert_response :success
    assert_equal original_parent, @club.reload.parent_organisation_id
  end

  test "an admin may still re-parent" do
    # Otherwise the fix above would have removed a capability rather than narrowed
    # it, and the federation tree could never be reorganised.
    sign_in_as(@admin)

    patch_json "/api/v1/organisations/#{@club.id}",
               organisation: { parent_organisation_id: @australia.id }

    assert_response :success
    assert_equal @australia.id, @club.reload.parent_organisation_id
  end

  test "an admin can give a standalone club a parent" do
    # The move that actually builds the tree: Maroubra is a root with no parent to
    # change, and giving it one is the common case rather than the exception.
    sign_in_as(@admin)
    maroubra = organisations(:maroubra_club)
    assert_nil maroubra.parent_organisation_id

    patch_json "/api/v1/organisations/#{maroubra.id}",
               organisation: { parent_organisation_id: @fivb.id }

    assert_response :success
    maroubra.reload
    assert_equal @fivb.id, maroubra.parent_organisation_id
    assert_equal 1, maroubra.depth

    # And it reads back the way the tree view needs it, without a second call.
    get "/api/v1/organisations/#{maroubra.id}"
    assert_response :success
    assert_equal @fivb.id, json["parent_organisation_id"]
    assert_equal "FIVB", json["parent_organisation"]["name"]
    assert_equal 1, json["depth"]
  end

  test "an acronym round-trips through the API and is upcased server-side" do
    sign_in_as(@admin)

    patch_json "/api/v1/organisations/#{@club.id}", organisation: { acronym: " sbvc " }

    assert_response :success
    # Normalised on write, so the client never has to know the stored casing.
    assert_equal "SBVC", json["acronym"]
    assert_equal "SBVC", @club.reload.acronym
  end

  test "a bad acronym is refused with a 422 and nothing is stored" do
    sign_in_as(@admin)
    original = @club.reload.acronym
    assert_nil original, "the fixture starts with no acronym"

    patch_json "/api/v1/organisations/#{@club.id}", organisation: { acronym: "Not/A/Club" }

    assert_response :unprocessable_entity
    assert_nil @club.reload.acronym
  end

  test "clearing the acronym is allowed" do
    # Nullable by design: an organisation may have no short form.
    sign_in_as(@admin)
    @club.update!(acronym: "SBVC")

    patch_json "/api/v1/organisations/#{@club.id}", organisation: { acronym: "" }

    assert_response :success
    assert_nil @club.reload.acronym
  end

  test "can_manage_members is narrower than can_edit and matches the server" do
    # The bug this pins: the roster was gated on `can_edit`, which admits a curator
    # and a club's creator. Neither runs anybody's roster, so those users saw invite
    # and role controls that the endpoint answered 403.
    [ users(:four), users(:three) ].each do |user|
      sign_in_as(user)
      get "/api/v1/organisations"
      row = json["data"].find { |r| r["id"] == @club.id }

      assert_not row["can_manage_members"],
                 "#{user.email_address} can edit but must not manage the roster"

      # And the flag must not disagree with what the endpoint actually allows.
      post_json "/api/v1/organisations/#{@club.id}/members", membership: { person_id: people(:national_official).id }
      assert_equal 403, response.status, "flag and endpoint disagree for #{user.email_address}"
    end
  end

  test "a curator can edit an organisation but not manage its roster" do
    sign_in_as(@curator)
    get "/api/v1/organisations/#{@club.id}"

    assert json["can_edit"], "oversight may correct the record"
    assert_not json["can_manage_members"], "but is not an officer of this club"
  end

  test "the club's owner may manage the roster" do
    sign_in_as(users(:six))
    get "/api/v1/organisations/#{@club.id}"

    assert json["can_manage_members"]
  end

  # --- who may edit an organisation -------------------------------------------

  test "a curator may edit an organisation" do
    sign_in_as(@curator)

    patch_json "/api/v1/organisations/#{@club.id}", organisation: { name: "Renamed By Curator" }

    assert_response :success
    assert_equal "Renamed By Curator", @club.reload.name
  end

  test "the club's owner may edit it" do
    sign_in_as(users(:six)) # Maria Silva, owner of the Sydney club

    patch_json "/api/v1/organisations/#{@club.id}", organisation: { name: "Renamed By Owner" }

    assert_response :success
    assert_equal "Renamed By Owner", @club.reload.name
  end

  test "the creator may edit it while they are still a member" do
    # Maria Silva owns this club, so her officer role is downgraded to a plain member
    # first: otherwise the request would be authorised by the officer path and the
    # test would prove nothing about `created_by_person`.
    officer = organisation_memberships(:owner_of_sydney_club)
    officer.update!(role: "member")
    creator = officer.person
    @club.update!(created_by_person: creator)
    assert_equal creator.id, @club.reload.created_by_person_id
    assert_not @club.manageable_by?(creator), "only the creator grant remains"

    sign_in_as(users(:six))

    patch_json "/api/v1/organisations/#{@club.id}", organisation: { name: "Renamed By Creator" }

    assert_response :success
    assert_equal "Renamed By Creator", @club.reload.name
  end

  test "the creator may no longer edit it once their membership has ended" do
    # The whole reason the creator grant is gated on membership: `created_by_person`
    # is never cleared, so keying on it alone would let a resigned founder keep
    # renaming the club forever while their roster rights had correctly lapsed.
    officer = organisation_memberships(:owner_of_sydney_club)
    officer.update!(role: "member")
    creator = officer.person
    @club.update!(created_by_person: creator)
    assert_equal creator.id, @club.reload.created_by_person_id
    assert_not @club.manageable_by?(creator), "still only reachable via the creator grant"

    officer.end!
    assert_not @club.editable_by?(creator), "the model agrees before the request is made"

    sign_in_as(users(:six))

    patch_json "/api/v1/organisations/#{@club.id}", organisation: { name: "After Resigning" }

    assert_response :forbidden
    assert_equal "Sydney Beach Volleyball Club", @club.reload.name
  end

  test "can_edit is reported per organisation rather than per role" do
    sign_in_as(users(:six)) # owns the Sydney club, nothing else

    get "/api/v1/organisations"

    rows = json["data"].index_by { |row| row["id"] }
    assert rows[@club.id]["can_edit"], "the club's own officer may edit it"
    assert_not rows[@nsw.id]["can_edit"], "but not an unrelated federation above it"
  end

  test "can_edit matches what the endpoint actually allows" do
    # The flag drives the SPA, so a mismatch would render a control that 403s.
    [ users(:six), users(:four), users(:three) ].each do |user|
      sign_in_as(user)
      get "/api/v1/organisations"
      flag = json["data"].find { |row| row["id"] == @club.id }["can_edit"]

      patch_json "/api/v1/organisations/#{@club.id}", organisation: { name: "Probe" }
      expected = response.status.between?(200, 299)
      assert_equal flag, expected,
                   "can_edit=#{flag} disagrees with #{response.status} for #{user.email_address}"
    end
  end

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

  test "a member added without a status is active immediately, not an invitation" do
    # Adding somebody to your own roster is a record-keeping act, not a request.
    # It used to default to `pending` on the principle that "an invitation is not a
    # grant" — but nothing could accept an invitation (no endpoint, no inbox, and no
    # channel at all for an accountless person), so the officer had to make a second
    # call to clear a state only they could move.
    sign_in_as(users(:six))

    post_membership(@club, people(:national_official))

    assert_response :created
    assert_equal "active", json["status"]
    # Effective at once: no second call, and the person is a member now.
    assert_includes @club.reload.members.map(&:id), people(:national_official).id
  end

  test "pending remains available as an explicit choice meaning not yet active" do
    sign_in_as(users(:six))

    post_membership(@club, people(:national_official), status: "pending")

    assert_response :created
    assert_equal "pending", json["status"]
  end

  test "ending a membership keeps the record and stamps left_at" do
    sign_in_as(users(:six))
    membership = organisation_memberships(:club_player)

    delete "/api/v1/organisations/#{@club.id}/members/#{membership.person_id}"

    assert_response :success
    assert_equal "ended", json.dig("membership", "status")
    # Not deleted — a historical assessment must still be explicable.
    assert OrganisationMembership.exists?(membership.id)
    assert_not_nil OrganisationMembership.find(membership.id).left_at
  end

  # --- invitations ------------------------------------------------------------

  test "withdrawing an unaccepted invitation removes the row rather than faking one" do
    # A `pending` membership records no stint. Ending it would write a `left_at`
    # saying the person left a club they never joined — the fabricated history the
    # membership model exists to prevent.
    sign_in_as(@admin)
    invitation = organisation_memberships(:pending_academy_member)
    academy_id = invitation.organisation_id
    person_id = invitation.person_id
    assert_predicate invitation, :pending?

    delete "/api/v1/organisations/#{academy_id}/members/#{person_id}"

    assert_response :success
    assert json["removed"]
    assert_equal person_id, json["person_id"]
    assert_not OrganisationMembership.exists?(invitation.id)
  end

  test "withdrawing an invitation makes the organisation deletable" do
    # The reason withdrawal is worth having: the Academy's only membership was an
    # invitation, so without this the delete guard was permanently unsatisfiable and
    # the only route to deleting it wrote a false departure.
    sign_in_as(@admin)
    academy = organisations(:sydney_academy)
    assert academy.organisation_memberships.pending.exists?
    assert_not academy.deletable?

    pending = academy.organisation_memberships.pending.first
    delete "/api/v1/organisations/#{academy.id}/members/#{pending.person_id}"
    assert_response :success

    assert_predicate academy.reload, :deletable?
    delete "/api/v1/organisations/#{academy.id}"
    assert_response :success
    assert_not Organisation.exists?(academy.id)
  end

  test "a real member's departure is never treated as a withdrawn invitation" do
    sign_in_as(users(:six))
    membership = organisation_memberships(:club_player)

    delete "/api/v1/organisations/#{@club.id}/members/#{membership.person_id}"

    assert_not json["removed"]
    assert OrganisationMembership.exists?(membership.id)
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

  test "a coach who is not an officer may not edit an organisation" do
    # `users(:six)` owns this very club, so the refusal needs somebody genuinely
    # outside it: `users(:four)` is a curator and `users(:three)` is a coach with no
    # Person at all.
    outsider = users(:three)
    sign_in_as(outsider)

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

  # --- joining (self-service) ------------------------------------------------

  test "a coach can join an organisation they belong to nothing yet" do
    # Self-service. Distinct from `members`, which writes *somebody else's* row and
    # is gated on `can_manage_members` — this writes your own and must not be.
    # @coach is an owner of Sydney Beach Volleyball Club and of nothing else, so
    # joining Volleyball Australia is a genuine first-time join.
    sign_in_as(@coach)

    assert_difference "OrganisationMembership.count", 1 do
      post join_api_v1_organisation_path(@australia)
    end

    assert_response :created
    membership = OrganisationMembership.find_by(
      organisation: @australia, person: @coach.person
    )
    assert_equal "member", membership.role
    assert_equal "active", membership.status
    assert_not_nil membership.joined_at
    assert_nil membership.left_at
  end

  test "joining is never a way to grant yourself a management role" do
    sign_in_as(@coach)

    post_json join_api_v1_organisation_path(@australia),
              role: "owner", status: "active"

    assert_response :created
    membership = OrganisationMembership.find_by(
      organisation: @australia, person: @coach.person
    )
    assert_equal "member", membership.role
    assert_equal "active", membership.status
  end

  test "joining an organisation twice conflicts rather than duplicating" do
    sign_in_as(@coach)
    post join_api_v1_organisation_path(@australia)
    assert_response :created

    assert_no_difference "OrganisationMembership.count" do
      post join_api_v1_organisation_path(@australia)
    end

    assert_response :conflict
    assert_match(/already a member/, json["error"])
  end

  test "rejoining after leaving reactivates the same row rather than adding one" do
    # §2.5: the earlier stint stays on the record, so the row count must not move.
    sign_in_as(@coach)
    left = @australia.organisation_memberships.create!(
      person: @coach.person, role: "member", status: "ended",
      joined_at: 1.year.ago, left_at: 1.month.ago
    )

    assert_no_difference "OrganisationMembership.count" do
      post join_api_v1_organisation_path(@australia)
    end

    assert_response :created
    reloaded = OrganisationMembership.find(left.id)
    assert_equal "active", reloaded.status
    assert_nil reloaded.left_at
    assert_not_nil reloaded.joined_at
  end

  test "an account with no person cannot join, because there is nothing to join as" do
    # users(:four) is a curator — a training manager, so it passes the read gate —
    # but has no account, and therefore no Person.
    curator = users(:four)
    assert_nil curator.person

    sign_in_as(curator)
    post join_api_v1_organisation_path(@australia)

    assert_response :unprocessable_entity
    assert_match(/no person record/, json["errors"].first)
  end

  test "an archived organisation does not accept new members" do
    sign_in_as(@coach)
    retired = organisations(:retired_association)

    post join_api_v1_organisation_path(retired)

    assert_response :unprocessable_entity
    assert_match(/archived/, json["errors"].first)
  end

  test "a guest may not join an organisation" do
    post join_api_v1_organisation_path(@australia)

    assert_response :unauthorized
  end

  test "a guest may not create one" do
    post_json "/api/v1/organisations", organisation: { name: "Guest Club" }
    assert_response :unauthorized
  end
end
