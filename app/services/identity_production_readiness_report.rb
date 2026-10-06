# Read-only aggregate checks for the identity production migration runbook.
# This report intentionally emits no names, emails, or record identifiers.
class IdentityProductionReadinessReport
  REQUIRED_MIGRATIONS = %w[
    20261003000001
    20261003000002
    20261003000003
    20261003000004
    20261004000001
    20261005000001
    20261005000002
    20261006000001
    20261006000002
    20261006000003
    20261006000004
    20261006100001
    20261006100002
    20261006100003
    20261006100004
    20261006100005
    20261006100006
    20261006100007
  ].freeze

  REQUIRED_TABLES = %w[
    users people accounts contact_details player_profiles coach_profiles assessments
    training_session_participants assessment_session_participants
    organisation_memberships group_memberships player_coaches person_aliases
    player_claims player_claim_invitations person_account_invitations
    claim_invitations person_consolidations profile_merges
  ].freeze

  ORPHAN_CHECKS = {
    "accounts_without_users" => [ "accounts", "user_id", "users" ],
    "accounts_without_people" => [ "accounts", "person_id", "people" ],
    "player_profiles_without_people" => [ "player_profiles", "person_id", "people" ],
    "coach_profiles_without_people" => [ "coach_profiles", "person_id", "people" ],
    "assessments_without_player_profiles" => [ "assessments", "player_profile_id", "player_profiles" ],
    "assessments_without_coach_profiles" => [ "assessments", "coach_profile_id", "coach_profiles" ],
    "training_participants_without_player_profiles" => [ "training_session_participants", "player_profile_id", "player_profiles" ],
    "assessment_participants_without_player_profiles" => [ "assessment_session_participants", "player_profile_id", "player_profiles" ],
    "organisation_memberships_without_people" => [ "organisation_memberships", "person_id", "people" ],
    "group_memberships_without_people" => [ "group_memberships", "person_id", "people" ],
    "claims_without_people" => [ "player_claims", "person_id", "people" ],
    "claims_without_initiators" => [ "player_claims", "initiated_by_person_id", "people" ],
    "claims_without_reviewers" => [ "player_claims", "reviewed_by_person_id", "people" ],
    "invitations_without_player_profiles" => [ "player_claim_invitations", "player_profile_id", "player_profiles" ],
    "invitations_without_creators" => [ "player_claim_invitations", "created_by_person_id", "people" ],
    "invitations_without_users" => [ "player_claim_invitations", "used_by_person_id", "people" ],
    "person_invitations_without_people" => [ "person_account_invitations", "person_id", "people" ],
    "person_invitations_without_issuers" => [ "person_account_invitations", "invited_by_id", "users" ],
    "person_invitations_without_users" => [ "person_account_invitations", "used_by_id", "users" ],
    "claim_invitation_issuers_without_users" => [ "claim_invitations", "invited_by_id", "users" ],
    "claim_invitation_users_without_users" => [ "claim_invitations", "used_by_id", "users" ],
    "consolidations_without_source_people" => [ "person_consolidations", "source_person_id", "people" ],
    "consolidations_without_canonical_people" => [ "person_consolidations", "canonical_person_id", "people" ],
    "consolidations_without_performers" => [ "person_consolidations", "performed_by_id", "users" ],
    "people_without_merge_actors" => [ "people", "merged_by_id", "users" ],
    "person_aliases_without_people" => [ "person_aliases", "person_id", "people" ],
    "organisation_memberships_without_organisations" => [ "organisation_memberships", "organisation_id", "organisations" ],
    "group_memberships_without_groups" => [ "group_memberships", "group_id", "groups" ],
    "assessment_sessions_without_coaches" => [ "assessment_sessions", "coach_profile_id", "coach_profiles" ],
    "assessment_sessions_without_groups" => [ "assessment_sessions", "group_id", "groups" ],
    "player_coach_links_without_players" => [ "player_coaches", "player_profile_id", "player_profiles" ],
    "player_coach_links_without_coaches" => [ "player_coaches", "coach_profile_id", "coach_profiles" ]
  }.freeze

  def call
    @connection = ActiveRecord::Base.connection
    anomalies = []
    migration_versions = @connection.select_values("SELECT version FROM schema_migrations")
    missing_tables = REQUIRED_TABLES.reject { |table| table_exists?(table) }

    add_anomaly(anomalies, "required_tables_missing", "blocker", missing_tables.length,
                "Restore the expected application schema before running identity migrations.") unless missing_tables.empty?

    add_anomaly(anomalies, "required_migrations_pending", "warning",
                (REQUIRED_MIGRATIONS - migration_versions).length,
                "Apply the identity migrations after backup and preflight approval.") unless (REQUIRED_MIGRATIONS - migration_versions).empty?
    add_anomaly(anomalies, "accounts_with_duplicate_person", "blocker", duplicate_count(:accounts, :person_id),
                "Resolve account ownership explicitly; do not auto-merge accounts.")
    add_anomaly(anomalies, "accounts_without_person", "warning", Account.where(person_id: nil).count,
                "Review unlinked accounts and confirm they are expected onboarding records.")
    add_anomaly(anomalies, "coach_profiles_without_person", "blocker", CoachProfile.where(person_id: nil).count,
                "CoachProfiles require a Person; investigate before deployment.")
    add_anomaly(anomalies, "duplicate_canonical_emails", "warning", duplicate_canonical_email_groups,
                "Review matching email groups; this report does not decide whether records describe the same person.")
    add_anomaly(anomalies, "duplicate_canonical_names", "warning", duplicate_canonical_name_groups,
                "Review matching name groups as possible duplicates; common names are not automatically merged.")
    if @connection.column_exists?(:player_profiles, :display_name)
      add_anomaly(anomalies, "player_profiles_without_person_or_name", "warning",
                  PlayerProfile.where(person_id: nil).where("display_name IS NULL OR display_name = ''").count,
                  "These profiles cannot be identified in the claim workflow; curate their display names.")
    end
    add_anomaly(anomalies, "invalid_player_profile_status", "blocker",
                PlayerProfile.where.not(status: PlayerProfile::STATUSES).count,
                "Restore a valid PlayerProfile lifecycle status before deployment.")
    add_anomaly(anomalies, "invalid_coach_profile_status", "blocker",
                CoachProfile.where.not(status: CoachProfile::STATUSES).count,
                "Restore a valid CoachProfile lifecycle status before deployment.")

    if table_exists?(:player_claims)
      add_anomaly(anomalies, "invalid_claim_status", "blocker",
                  PlayerClaim.where.not(status: PlayerClaim::STATUSES).count,
                  "Restore a valid claim lifecycle status before deployment.")
      add_anomaly(anomalies, "pending_claims_on_linked_profiles", "blocker",
                  PlayerClaim.pending.where(claimable_type: "PlayerProfile",
                                            claimable_id: PlayerProfile.where.not(person_id: nil).select(:id)).count +
                    PlayerClaim.pending.where(claimable_type: "CoachProfile",
                                              claimable_id: CoachProfile.where.not(person_id: nil).select(:id)).count,
                  "Reconcile the claim and existing profile association before enabling claims.")
      add_anomaly(anomalies, "duplicate_pending_claim_profiles", "blocker",
                  duplicate_claimables("player_claims", status: "pending"),
                  "Resolve duplicate pending claims before relying on the partial unique index.")
      add_anomaly(anomalies, "claims_without_claimables", "blocker",
                  polymorphic_orphan_count("player_claims", "claimable_type", "claimable_id",
                                           "PlayerProfile" => "player_profiles", "CoachProfile" => "coach_profiles"),
                  "Restore each claim's polymorphic subject before enabling claims.")
    end
    if table_exists?(:player_claim_invitations)
      add_anomaly(anomalies, "invalid_invitation_status", "blocker",
                  PlayerClaimInvitation.where.not(status: PlayerClaimInvitation::STATUSES).count,
                  "Restore a valid invitation lifecycle status before deployment.")
      add_anomaly(anomalies, "expired_active_invitations", "warning",
                  PlayerClaimInvitation.active.where("expires_at <= ?", Time.current).count,
                  "Expired invitations are rejected at redemption and transition to expired on use/revoke.")
      add_anomaly(anomalies, "duplicate_active_invitations_per_profile", "blocker",
                  duplicate_count(:player_claim_invitations, :player_profile_id, "status = 'active'"),
                  "Resolve duplicate active invitations before relying on the partial unique index.")
    end
    if table_exists?(:claim_invitations)
      add_anomaly(anomalies, "invalid_unified_invitation_status", "blocker",
                  ClaimInvitation.where.not(status: ClaimInvitation::STATUSES).count,
                  "Restore a valid unified invitation lifecycle status before deployment.")
      add_anomaly(anomalies, "used_invitations_without_actor", "blocker",
                  ClaimInvitation.where(status: "used", used_by_id: nil).count,
                  "Reconcile the actor for each used invitation before deployment.")
      add_anomaly(anomalies, "used_invitations_without_timestamp", "blocker",
                  ClaimInvitation.where(status: "used", used_at: nil).count,
                  "Restore the redemption timestamp for each used invitation.")
      add_anomaly(anomalies, "revoked_invitations_without_timestamp", "blocker",
                  ClaimInvitation.where(status: "revoked", revoked_at: nil).count,
                  "Restore the revocation timestamp for each revoked invitation.")
      add_anomaly(anomalies, "duplicate_active_invitations_per_claimable", "blocker",
                  duplicate_claimables("claim_invitations", status: "active"),
                  "Resolve duplicate active invitations for the same subject before deployment.")
      add_anomaly(anomalies, "invitations_without_claimables", "blocker",
                  polymorphic_orphan_count("claim_invitations", "claimable_type", "claimable_id",
                                           "PlayerProfile" => "player_profiles", "CoachProfile" => "coach_profiles", "Person" => "people"),
                  "Restore each invitation's polymorphic subject before deployment.")
    end
    if table_exists?(:profile_merges)
      add_anomaly(anomalies, "profile_merges_without_sources", "blocker",
                  polymorphic_orphan_count("profile_merges", "source_profile_type", "source_profile_id",
                                           "PlayerProfile" => "player_profiles", "CoachProfile" => "coach_profiles"),
                  "Restore each profile merge's source before deployment.")
      add_anomaly(anomalies, "profile_merges_without_canonicals", "blocker",
                  polymorphic_orphan_count("profile_merges", "canonical_profile_type", "canonical_profile_id",
                                           "PlayerProfile" => "player_profiles", "CoachProfile" => "coach_profiles"),
                  "Restore each profile merge's canonical profile before deployment.")
      add_anomaly(anomalies, "profile_merges_without_accounts", "blocker",
                  orphan_count("profile_merges", "merged_by_account_id", "accounts"),
                  "Restore each profile merge's actor Account before deployment.")
    end
    if @connection.column_exists?(:people, :merged_into_id)
      add_anomaly(anomalies, "merged_people_without_canonical_person", "blocker",
                  Person.where(status: "merged", merged_into_id: nil).count,
                  "Repair merged-person references before deploying consolidation APIs.")
      add_anomaly(anomalies, "unmerged_people_with_canonical_person", "blocker",
                  Person.where.not(status: "merged").where.not(merged_into_id: nil).count,
                  "Repair status/reference disagreement before deploying consolidation APIs.")
    end
    if table_exists?(:person_consolidations)
      add_anomaly(anomalies, "consolidation_source_not_marked_merged", "blocker",
                  PersonConsolidation.joins("INNER JOIN people ON people.id = person_consolidations.source_person_id")
                                    .where.not(people: { status: "merged" }).count,
                  "Reconcile consolidation audit state with source Person state.")
    end

    orphan_counts = ORPHAN_CHECKS.each_with_object({}) do |(name, (table, foreign_key, target)), result|
      result[name] = orphan_count(table, foreign_key, target) if table_exists?(table) && table_exists?(target) && @connection.column_exists?(table, foreign_key)
    end
    orphan_counts.each do |name, count|
      add_anomaly(anomalies, name, "blocker", count, "Restore referential integrity before deployment.") if count.positive?
    end

    {
      generated_at: Time.current.utc.iso8601,
      environment: Rails.env,
      read_only: true,
      required_identity_migrations: REQUIRED_MIGRATIONS.index_with { |version| migration_versions.include?(version) },
      missing_required_tables: missing_tables,
      counts: counts,
      cardinality: {
        people_with_multiple_player_profiles: multiple_profile_people_count(PlayerProfile),
        people_with_multiple_coach_profiles: multiple_profile_people_count(CoachProfile),
        unlinked_player_profiles: PlayerProfile.where(person_id: nil).count,
        accounts_without_person: Account.where(person_id: nil).count,
        duplicate_canonical_email_groups: duplicate_canonical_email_groups,
        duplicate_canonical_name_groups: duplicate_canonical_name_groups
      },
      preservation_counts: preservation_counts,
      orphan_counts: orphan_counts,
      anomalies: anomalies,
      blockers: anomalies.count { |anomaly| anomaly[:severity] == "blocker" },
      warnings: anomalies.count { |anomaly| anomaly[:severity] == "warning" }
    }
  ensure
    @connection = nil
  end

  private

  def counts
    {
      people: Person.count,
      accounts: Account.count,
      player_profiles: PlayerProfile.count,
      coach_profiles: CoachProfile.count,
      organisation_memberships: OrganisationMembership.count,
      group_memberships: GroupMembership.count
    }.tap do |result|
      result[:player_claims] = PlayerClaim.count if table_exists?(:player_claims)
      result[:player_claim_invitations] = PlayerClaimInvitation.count if table_exists?(:player_claim_invitations)
      result[:person_account_invitations] = PersonAccountInvitation.count if table_exists?(:person_account_invitations)
      result[:claim_invitations] = ClaimInvitation.count if table_exists?(:claim_invitations)
      result[:person_consolidations] = PersonConsolidation.count if table_exists?(:person_consolidations)
      result[:profile_merges] = ProfileMerge.count if table_exists?(:profile_merges)
    end
  end

  def preservation_counts
    {
      assessments: [ "assessments", Assessment ],
      training_session_participants: [ "training_session_participants", TrainingSessionParticipant ],
      assessment_session_participants: [ "assessment_session_participants", AssessmentSessionParticipant ],
      player_coach_relationships: [ "player_coaches", PlayerCoach ],
      organisation_memberships: [ "organisation_memberships", OrganisationMembership ],
      group_memberships: [ "group_memberships", GroupMembership ],
      person_aliases: [ "person_aliases", PersonAlias ]
    }.transform_values { |table, model| table_exists?(table) ? model.count : nil }
  end

  def duplicate_count(table, column, condition = nil)
    scope = @connection.quote_table_name(table)
    field = @connection.quote_column_name(column)
    predicates = [ "#{field} IS NOT NULL", condition ].compact
    where_sql = "WHERE #{predicates.join(' AND ')}"
    @connection.select_value("SELECT COUNT(*) FROM (SELECT #{field} FROM #{scope} #{where_sql} GROUP BY #{field} HAVING COUNT(*) > 1) duplicates").to_i
  end

  def duplicate_claimables(table, status:)
    source_table = @connection.quote_table_name(table)
    @connection.select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM (
        SELECT claimable_type, claimable_id
        FROM #{source_table}
        WHERE status = #{@connection.quote(status)}
          AND claimable_type IS NOT NULL
          AND claimable_id IS NOT NULL
        GROUP BY claimable_type, claimable_id
        HAVING COUNT(*) > 1
      ) duplicate_claimables
    SQL
  end

  def table_exists?(table)
    @connection.data_source_exists?(table)
  end

  def orphan_count(table, foreign_key, target)
    source_table = @connection.quote_table_name(table)
    target_table = @connection.quote_table_name(target)
    foreign_key = @connection.quote_column_name(foreign_key)
    @connection.select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM #{source_table} source
      LEFT JOIN #{target_table} target ON target.id = source.#{foreign_key}
      WHERE source.#{foreign_key} IS NOT NULL AND target.id IS NULL
    SQL
  end

  def polymorphic_orphan_count(table, type_column, id_column, targets)
    return 0 unless table_exists?(table)

    source_table = @connection.quote_table_name(table)
    type_field = @connection.quote_column_name(type_column)
    id_field = @connection.quote_column_name(id_column)
    missing_targets = targets.sum do |type, target|
      next 0 unless table_exists?(target)

      target_table = @connection.quote_table_name(target)
      @connection.select_value(<<~SQL).to_i
        SELECT COUNT(*)
        FROM #{source_table} source
        LEFT JOIN #{target_table} target ON target.id = source.#{id_field}
        WHERE source.#{type_field} = #{@connection.quote(type)}
          AND (source.#{id_field} IS NULL OR target.id IS NULL)
      SQL
    end
    unknown_types = @connection.select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM #{source_table}
      WHERE #{type_field} NOT IN (#{targets.keys.map { |type| @connection.quote(type) }.join(', ')})
         OR #{type_field} IS NULL
    SQL
    missing_targets + unknown_types
  end

  def multiple_profile_people_count(profile_class)
    profile_class.where.not(person_id: nil).group(:person_id).having("COUNT(*) > 1").count.length
  end

  def duplicate_canonical_email_groups
    Person.canonical.where.not(email: [ nil, "" ]).group("LOWER(BTRIM(email))").having("COUNT(*) > 1").count.length
  end

  def duplicate_canonical_name_groups
    Person.canonical.group("LOWER(BTRIM(first_name || ' ' || COALESCE(last_name, '')))").having("COUNT(*) > 1").count.length
  end

  def add_anomaly(list, code, severity, count, remediation)
    return if count.zero?

    list << { code: code, severity: severity, count: count, remediation: remediation }
  end
end
