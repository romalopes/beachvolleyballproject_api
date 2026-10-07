# Turns a nested `profile:` row into a linked PlayerProfile.
#
# Both the training-session form and the assessment-session form let a coach
# enter someone new instead of searching for an existing player. The sequence is
# identical and easy to get subtly wrong, so it lives here rather than being
# copied into a second controller and left to drift:
#
#   * the Person is built through PersonCreationService, so `creation_source` and
#     `created_by` are stamped exactly as they are for every other person staff
#     record;
#   * a PlayerProfile is attached and the two are persisted together — no Account
#     is created, and the player is usable immediately;
#   * the row's `player_profile_id` is filled in, because the nested
#     `accepts_nested_attributes_for` that runs next resolves a participant by
#     profile id, not by person.
#
# `RecordInvalid` is left to bubble up so the caller renders the person's own
# validation errors instead of a generic failure.
class InlineParticipantResolver
  # The attributes a coach may supply for a person they are recording — the same
  # set the standalone player/coach forms accept.
  PROFILE_ATTRIBUTES = %i[display_name preferred_position level visibility].freeze
  # Controllers use this name while their nested request key is migrated from
  # `person` to `profile`.
  PERSON_ATTRIBUTES = PROFILE_ATTRIBUTES

  def initialize(created_by:)
    @created_by = created_by
  end

  # Mutates the permitted nested rows in place: a row that carried `person:`
  # comes back carrying `player_profile_id`, which is what the association
  # expects. Rows that already name a profile, or carry no person at all, are
  # left exactly as they were.
  def call(rows)
    Array(rows).each do |row|
      next unless row.respond_to?(:delete)

      profile_attrs = row.delete("profile") || row.delete(:profile)
      next if profile_attrs.blank?
      next if row[:player_profile_id].present? || row["player_profile_id"].present?

      profile = PlayerProfile.create!(profile_attrs.slice(*PROFILE_ATTRIBUTES).merge(display_name: profile_attrs[:display_name] || profile_attrs["display_name"]))
      ProfileOwnership.stamp!(profile, @created_by)
      profile.save!
      row[:player_profile_id] = profile.id
    end

    rows
  end
end
