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
    names = known_names
    return [] if names.empty?

    available = PlayerProfile.active
                            .where(person_id: nil)
                            .where.not(id: PlayerClaim.pending.select(:player_profile_id))
                            .visible_to(@user)

    exact_names = names.map { |name| normalize(name) }.reject(&:blank?).uniq
    exact = if exact_names.empty?
      PlayerProfile.none
    else
      available.where("regexp_replace(lower(trim(display_name)), '[^[:alnum:]]', '', 'g') IN (?)", exact_names)
    end

    partial_terms = names.flat_map { |name| name.split(/[^\p{Alnum}]+/u) }
                         .map { |term| term.strip.downcase }
                         .select { |term| term.length >= MIN_PARTIAL_LENGTH }
                         .uniq
    partial = if partial_terms.empty?
      PlayerProfile.none
    else
      conditions = partial_terms.map { "display_name ILIKE ?" }.join(" OR ")
      available.where(conditions, *partial_terms.map { |term| "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" })
    end

    exact_profiles = exact.order(Arel.sql("LOWER(player_profiles.display_name)"), :id).limit(LIMIT).to_a
    remainder = LIMIT - exact_profiles.length
    partial_profiles = if remainder.positive?
      partial.where.not(id: exact_profiles.map(&:id))
             .order(Arel.sql("LOWER(player_profiles.display_name)"), :id)
             .limit(remainder).to_a
    else
      []
    end
    exact_profiles.map { |profile| Candidate.new(player_profile: profile, match_type: "exact_name") } +
      partial_profiles.map { |profile| Candidate.new(player_profile: profile, match_type: "partial_name") }
  end

  private

  def known_names
    [ @person.full_name, @person.first_name, @person.last_name ] + @person.person_aliases.map(&:full_name)
  end

  def normalize(value)
    value.to_s.downcase.gsub(/[^\p{Alnum}]/u, "")
  end
end
