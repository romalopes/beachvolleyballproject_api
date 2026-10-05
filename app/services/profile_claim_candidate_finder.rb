# Name-based suggestions over profiles the centralized claimability policy
# already permits. Names are hints only; the claimant must still submit a claim.
class ProfileClaimCandidateFinder
  LIMIT = 20
  MIN_PARTIAL_LENGTH = 3

  Candidate = Data.define(:profile, :type, :match_type) do
    def as_json(*)
      key = type == "PlayerProfile" ? :player_profile_id : :coach_profile_id
      {
        id: profile.id,
        claimable_type: type,
        claimable_id: profile.id,
        key => profile.id,
        display_name: profile.full_name,
        match_type: match_type,
        result_type: "candidate"
      }
    end
  end

  def initialize(person:, user:, type: "PlayerProfile")
    @person = person
    @user = user
    @type = type
  end

  def matches
    return [] unless ProfileClaimability::PROFILE_TYPES.include?(@type)

    available = ProfileClaimability.profiles_for(user: @user, type: @type)
                             .where.not(id: pending_subject_ids)
    names = ([ @person.full_name, @person.first_name, @person.last_name ] + @person.person_aliases.map(&:full_name))
            .map { |name| normalize(name) }.reject(&:blank?).uniq
    return [] if names.empty?

    exact = available.where("regexp_replace(lower(trim(display_name)), '[^[:alnum:]]', '', 'g') IN (?)", names)
    terms = names.flat_map { |name| name.split(/[^[:alnum:]]+/) }
                 .select { |term| term.length >= MIN_PARTIAL_LENGTH }.uniq
    partial = if terms.empty?
      available.none
    else
      available.where(terms.map { "display_name ILIKE ?" }.join(" OR "), *terms.map { |term| "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" })
    end

    exact_rows = exact.order(Arel.sql("LOWER(display_name)"), :id).limit(LIMIT).to_a
    remaining = LIMIT - exact_rows.length
    partial_rows = remaining.positive? ? partial.where.not(id: exact_rows.map(&:id)).order(Arel.sql("LOWER(display_name)"), :id).limit(remaining).to_a : []
    (exact_rows.map { |row| Candidate.new(profile: row, type: @type, match_type: "exact_name") } +
      partial_rows.map { |row| Candidate.new(profile: row, type: @type, match_type: "partial_name") })
  end

  private

  def pending_subject_ids
    polymorphic = PlayerClaim.pending.where(claimable_type: @type).select(:claimable_id)
    return polymorphic unless @type == "PlayerProfile"

    legacy = PlayerClaim.pending.where.not(player_profile_id: nil).select(:player_profile_id)
    PlayerProfile.where(id: polymorphic).or(PlayerProfile.where(id: legacy)).select(:id)
  end

  def normalize(value)
    value.to_s.downcase.gsub(/[^[:alnum:]]/, "")
  end
end
