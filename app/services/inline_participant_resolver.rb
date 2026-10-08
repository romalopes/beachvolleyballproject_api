# Turns a nested `person:` row into a linked PlayerProfile.
#
# Both the training-session form and the assessment-session form let a coach
# enter someone new instead of searching for an existing player. The sequence is
# identical and easy to get subtly wrong, so it lives here rather than being
# copied into a second controller and left to drift:
#
#   * an inline person's name is recorded as the PlayerProfile's display name;
#   * no Account is created, so the player is usable immediately without login
#     credentials or an account-linked contact record;
#   * the row's `player_profile_id` is filled in, because the nested
#     `accepts_nested_attributes_for` that runs next resolves a participant by
#     profile id, not by person.
#
# `RecordInvalid` is left to bubble up so the caller renders the person's own
# validation errors instead of a generic failure.
class InlineParticipantResolver
  # The legacy nested `profile:` payload is still accepted while callers migrate
  # to the public `person:` contract.
  PROFILE_ATTRIBUTES = %i[display_name preferred_position level visibility].freeze
  # Contact fields are accepted because the inline roster form uses the same
  # person shape as other identity forms. Profiles are intentionally accountless,
  # however, so only the supplied name is persisted here; creating an Account or
  # ContactDetail would incorrectly create login identity from a roster entry.
  PERSON_ATTRIBUTES = %i[first_name last_name email phone date_of_birth].freeze

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

      next if row[:player_profile_id].present? || row["player_profile_id"].present?

      person_attrs = row.delete("person") || row.delete(:person)
      profile_attrs = row.delete("profile") || row.delete(:profile)
      next if person_attrs.blank? && profile_attrs.blank?

      attributes = if person_attrs.present?
        { display_name: display_name_from(person_attrs) }
      else
        profile_attrs.slice(*PROFILE_ATTRIBUTES)
      end

      profile = PlayerProfile.new(attributes)
      ProfileOwnership.stamp!(profile, @created_by)
      profile.save!
      row[:player_profile_id] = profile.id
    end

    rows
  end

  private

  def display_name_from(person_attrs)
    [ person_attrs[:first_name] || person_attrs["first_name"],
      person_attrs[:last_name] || person_attrs["last_name"] ]
      .filter_map { |part| part.to_s.strip.presence }
      .join(" ")
  end
end
