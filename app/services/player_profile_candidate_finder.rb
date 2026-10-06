# Suggests visible, active, unlinked profiles whose recorded display name may
# match the signed-in Account's ContactDetail name. Results are hints only;
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

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def matches
    ProfileClaimCandidateFinder.new(account: @account, user: @user, type: "PlayerProfile").matches.map do |candidate|
      Candidate.new(player_profile: candidate.profile, match_type: candidate.match_type)
    end
  end

end
