# Suggests visible, active, unlinked profiles whose recorded display name may
# match the signed-in Person's current or previous names. Results are hints only;
# this service never changes a profile or creates a claim.
class PlayerProfileCandidateFinder
  LIMIT = 20
  MIN_PARTIAL_LENGTH = 3

  Candidate = Data.define(:player_profile, :match_type) do
    def as_json(*)
      {
        id: player_profile.id,
        player_profile_id: player_profile.id,
        display_name: player_profile.display_name,
        match_type: match_type,
        result_type: "candidate"
      }
    end
  end

  def initialize(person:, user:)
    @person = person
    @user = user
  end

  def matches
    ProfileClaimCandidateFinder.new(person: @person, user: @user, type: "PlayerProfile").matches.map do |candidate|
      Candidate.new(player_profile: candidate.profile, match_type: candidate.match_type)
    end
  end

  private

  def known_names
    [ @person.full_name, @person.first_name, @person.last_name ] + @person.person_aliases.map(&:full_name)
  end

  def normalize(value)
    value.to_s.downcase.gsub(/[^\p{Alnum}]/u, "")
  end
end
