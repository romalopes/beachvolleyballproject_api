# Read-only aggregate checks for the identity production migration runbook.
# This report intentionally emits no names, emails, or record identifiers.
class IdentityProductionReadinessReport
  REQUIRED_MIGRATIONS = %w[
    20261003000001
    20261003000002
    20261003000003
    20261003000004
    20261004000001
  ].freeze

  REQUIRED_TABLES = %w[
    people accounts player_profiles coach_profiles assessments
    training_session_participants assessment_session_participants
    organisation_memberships group_memberships player_coaches person_aliases
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
    "claims_without_player_profiles" => [ "player_claims", "player_profile_id", "player_profiles" ],
    "claims_without_people" => [ "player_claims", "person_id", "people" ],
    "claims_without_initiators" => [ "player_claims", "initiated_by_person_id", "people" ],
    "claims_without_reviewers" => [ "player_claims", "reviewed_by_person_id", "people" ],
    "invitations_without_player_profiles" => [ "player_claim_invitations", "player_profile_id", "player_profiles" ],
    "invitations_without_creators" => [ "player_claim_invitations", "created_by_person_id", "people" ],
    "invitations_without_users" => [ "player_claim_invitations", "used_by_person_id", "people" ],
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
                  PlayerClaim.pending.joins(:player_profile).where.not(player_profiles: { person_id: nil }).count,
                  "Reconcile the claim and existing profile association before enabling claims.")
      add_anomaly(anomalies, "duplicate_pending_claim_profiles", "blocker",
                  duplicate_count(:player_claims, :player_profile_id, "status = 'pending'"),
                  "Resolve duplicate pending claims before relying on the partial unique index.")
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
      result[name] = orphan_count(table, foreign_key, target) if table_exists?(table) && @connection.column_exists?(table, foreign_key)
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
      result[:person_consolidations] = PersonConsolidation.count if table_exists?(:person_consolidations)
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
