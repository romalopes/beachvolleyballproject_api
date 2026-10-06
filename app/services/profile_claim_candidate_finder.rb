# Name-based suggestions over profiles the centralized claimability policy
# already permits. Names are hints only; the claimant must still submit a claim.
class ProfileClaimCandidateFinder
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

  def initialize(person: nil, account: nil, user:, type: "PlayerProfile", query: nil, organisation_id: nil)
    @account = account || user&.account
    @person = person
    @user = user
    @type = type
    @query = query.to_s.strip
    @organisation_id = organisation_id.presence
  end

  def matches
    page(page: 1, per_page: 100).first
  end

  def page(page:, per_page:)
    return [ [], 0 ] unless ProfileClaimability::PROFILE_TYPES.include?(@type)
    return [ [], 0 ] unless @account

    available = ProfileClaimability.profiles_for(user: @user, type: @type)
    if @organisation_id
      membership = @account.organisation_memberships.active.find_by(organisation_id: @organisation_id)
      return [ [], 0 ] unless membership

      creator_accounts = Account.where(id: OrganisationMembership.where(organisation_id: @organisation_id, status: "active").select(:account_id))
      creator_users = creator_accounts.select(:user_id)
      available = available.where(created_by_account_id: creator_accounts)
        .or(available.where(created_by_id: creator_users))
    end

    unless @query.blank?
      return [ [], 0 ] if @query.length < MIN_PARTIAL_LENGTH
      matching = available.where("#{effective_name_sql} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%")
      total = matching.count
      rows = matching.order(Arel.sql("LOWER(display_name)"), :id)
        .offset((page - 1) * per_page).limit(per_page)
      return [ rows.map { |row| Candidate.new(profile: row, type: @type, match_type: "name_search") }, total ]
    end

    own_names = @account.player_profiles.pluck(:display_name) + @account.coach_profiles.pluck(:display_name)
    names = own_names
            .map { |name| normalize(name) }.reject(&:blank?).uniq
    return [ [], 0 ] if names.empty?

    exact = available.where("regexp_replace(lower(trim(#{effective_name_sql})), '[^[:alnum:]]', '', 'g') IN (?)", names)
    terms = names.flat_map { |name| name.split(/[^[:alnum:]]+/) }
                 .select { |term| term.length >= MIN_PARTIAL_LENGTH }.uniq
    partial = if terms.empty?
      available.none
    else
      available.where(terms.map { "#{effective_name_sql} ILIKE ?" }.join(" OR "), *terms.map { |term| "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" })
    end

    partial = partial.where.not(id: exact.select(:id))
    exact_count = exact.count
    partial_count = partial.count
    total = exact_count + partial_count
    offset = (page - 1) * per_page

    exact_rows = if offset < exact_count
      exact.order(Arel.sql("LOWER(display_name)"), :id).offset(offset).limit(per_page).to_a
    else
      []
    end
    remaining = per_page - exact_rows.length
    partial_offset = [ offset - exact_count, 0 ].max
    partial_rows = if remaining.positive?
      partial.order(Arel.sql("LOWER(display_name)"), :id).offset(partial_offset).limit(remaining).to_a
    else
      []
    end
    candidates = exact_rows.map { |row| Candidate.new(profile: row, type: @type, match_type: "exact_name") } +
      partial_rows.map { |row| Candidate.new(profile: row, type: @type, match_type: "partial_name") }
    [ candidates, total ]
  end

  private

  def effective_name_sql
    "NULLIF(trim(display_name), '')"
  end

  def normalize(value)
    value.to_s.downcase.gsub(/[^[:alnum:]]/, "")
  end
end
