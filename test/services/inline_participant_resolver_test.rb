require "test_helper"

# The resolver was extracted from TrainingSessionsController (plan S4) so the
# assessment-session form can reuse it. These tests exist because the inline
# flow — "add a player who does not have an account yet" — was only ever
# exercised indirectly through a controller test that did not cover it.
class InlineParticipantResolverTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
    @resolver = InlineParticipantResolver.new(created_by: @user)
  end

  test "creates a person and player profile and fills player_profile_id" do
    rows = [ { "person" => { "first_name" => "New", "last_name" => "Player" }, "status" => "invited" } ]

    @resolver.call(rows)

    created = Person.find_by(first_name: "New", last_name: "Player")
    assert_not_nil created
    assert_equal created.player_profile.id, rows.first[:player_profile_id]
  end

  test "stamps staff-creation provenance and the recording user" do
    rows = [ { "person" => { "first_name" => "Provenance" } } ]

    @resolver.call(rows)

    person = Person.find_by(first_name: "Provenance")
    assert_equal "coach_created", person.creation_source
    assert_equal @user.id, person.created_by_id
    assert_equal "active", person.status
  end

  test "never creates an account for the inline person" do
    rows = [ { "person" => { "first_name" => "Accountless" } } ]

    @resolver.call(rows)

    assert_nil Person.find_by(first_name: "Accountless").account
  end

  test "leaves the rest of the row untouched" do
    rows = [ { "person" => { "first_name" => "Kept" }, "status" => "confirmed", "notes" => "kept" } ]

    @resolver.call(rows)

    assert_equal "confirmed", rows.first["status"]
    assert_equal "kept", rows.first["notes"]
    assert_nil rows.first["person"]
  end

  # The controller hands the resolver ActionController::Parameters rows, which
  # are indifferent. This is the shape that actually runs in production, so it
  # is asserted directly rather than inferred from the plain-hash cases above.
  test "works on the indifferent rows a controller supplies" do
    rows = [
      ActionController::Parameters.new(
        "person" => { "first_name" => "Indifferent", "last_name" => "Player" },
        "status" => "invited"
      ).permit!
    ]

    @resolver.call(rows)

    person = Person.find_by(first_name: "Indifferent")
    assert_not_nil person
    assert_equal person.player_profile.id, rows.first[:player_profile_id]
    assert_equal "invited", rows.first[:status]
  end

  test "accepts symbol keys as well as the string keys controllers supply" do
    rows = [ { person: { first_name: "Symbol" } } ]

    @resolver.call(rows)

    assert_not_nil Person.find_by(first_name: "Symbol")
    assert_not_nil rows.first[:player_profile_id]
  end

  test "skips a row that already names a player profile" do
    profile = player_profiles(:john_player)
    rows = [ { "player_profile_id" => profile.id, "person" => { "first_name" => "Ignored" } } ]

    @resolver.call(rows)

    assert_equal profile.id, rows.first["player_profile_id"]
    assert_nil Person.find_by(first_name: "Ignored")
  end

  test "skips rows with no person" do
    rows = [ { "player_profile_id" => player_profiles(:pedro_player).id } ]

    @resolver.call(rows)

    assert_equal player_profiles(:pedro_player).id, rows.first["player_profile_id"]
  end

  test "ignores blank person attributes" do
    rows = [ { "person" => {} } ]

    assert_no_difference -> { Person.count } do
      @resolver.call(rows)
    end

    assert_nil rows.first[:player_profile_id]
  end

  test "tolerates nil and empty row collections" do
    assert_nil @resolver.call(nil)
    assert_equal [], @resolver.call([])
  end

  test "ignores entries that are not row hashes" do
    assert_nothing_raised { @resolver.call([ nil, 1, "person" ]) }
  end

  test "raises RecordInvalid so the caller can render the person's own errors" do
    rows = [ { "person" => { "last_name" => "NoFirstName" } } ]

    error = assert_raises(ActiveRecord::RecordInvalid) { @resolver.call(rows) }
    assert_includes error.record.errors[:first_name], "can't be blank"
  end

  test "does not leave a half-created person behind when the person is invalid" do
    rows = [ { "person" => { "last_name" => "Orphan" } } ]

    assert_no_difference -> { Person.count } do
      assert_raises(ActiveRecord::RecordInvalid) { @resolver.call(rows) }
    end
  end
end
