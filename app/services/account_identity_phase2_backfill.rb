# Repeatable data backfill and read-only preflight for the additive Phase 2
# Account-centric schema. Ambiguous mappings are reported, never guessed.
class AccountIdentityPhase2Backfill
  PROFILE_TYPES = {
    player_profiles: PlayerProfile,
    coach_profiles: CoachProfile
  }.freeze

  def call(dry_run: true)
    before = counts
    results = PROFILE_TYPES.each_with_object({}) do |(table, model), report|
      report[table] = {
        profiles_missing_account_link: model.where(account_id: nil).count,
        profiles_with_unknown_creator: model.where.not(created_by_id: nil)
          .where(created_by_account_id: nil)
          .where.not(created_by_id: Account.select(:user_id)).count,
        profile_people_without_account: model.where.not(person_id: nil).where(account_id: nil)
          .where.not(person_id: Account.select(:person_id)).count
      }
    end
    results[:ambiguous_person_account_mappings] = Person.joins(:account)
      .group("people.id").having("COUNT(accounts.id) > 1").count.length
    results[:ambiguous_creator_user_account_mappings] = User.joins(:account)
      .group("users.id").having("COUNT(accounts.id) > 1").count.length
    results[:profile_account_person_conflicts] = PROFILE_TYPES.each_with_object({}) do |(table, model), conflicts|
      quoted_table = model.connection.quote_table_name(table)
      conflicts[table] = model.where.not(account_id: nil).where(<<~SQL.squish).count
        EXISTS (
          SELECT 1 FROM accounts person_accounts
          WHERE person_accounts.person_id = #{quoted_table}.person_id
            AND person_accounts.id <> #{quoted_table}.account_id
        )
      SQL
    end
    results[:orphan_foreign_keys] = orphan_foreign_key_counts

    unless dry_run
      PROFILE_TYPES.each do |table, model|
        model.where(account_id: nil).where(person_id: Account.select(:person_id))
             .in_batches(of: 500) do |batch|
          batch.update_all(<<~SQL.squish)
            account_id = (
              SELECT accounts.id FROM accounts
              WHERE accounts.person_id = #{table}.person_id
            )
          SQL
        end
        model.where(created_by_account_id: nil)
             .where(created_by_id: Account.select(:user_id))
             .in_batches(of: 500) do |batch|
          batch.update_all(<<~SQL.squish)
            created_by_account_id = (
              SELECT accounts.id FROM accounts
              WHERE accounts.user_id = #{table}.created_by_id
            )
          SQL
        end
      end
    end

    {
      dry_run: dry_run,
      before: before,
      mapping_counts: results,
      after: dry_run ? before : counts,
      historical_reference_counts: historical_reference_counts
    }
  end

  private

  def counts
    {
      users: User.count,
      accounts: Account.count,
      people: Person.count,
      linked_profiles: PROFILE_TYPES.values.sum { |model| model.where.not(person_id: nil).count },
      profiles_linked_to_accounts: PROFILE_TYPES.values.sum { |model| model.where.not(account_id: nil).count },
      unlinked_profiles: PROFILE_TYPES.values.sum { |model| model.where(account_id: nil).count },
      accounts_without_contact_detail: Account.left_joins(:contact_detail).where(contact_details: { id: nil }).count
    }
  end

  def historical_reference_counts
    {
      assessments: Assessment.count,
      training_session_participants: TrainingSessionParticipant.count,
      assessment_session_participants: AssessmentSessionParticipant.count,
      player_coaches: PlayerCoach.count,
      organisation_memberships: OrganisationMembership.count,
      group_memberships: GroupMembership.count
    }
  end

  def orphan_foreign_key_counts
    profiles = PROFILE_TYPES.each_with_object({}) do |(table, model), result|
      result[table] = {
        person: model.left_joins(:person).where.not(person_id: nil).where(people: { id: nil }).count,
        account: model.left_joins(:account).where.not(account_id: nil).where(accounts: { id: nil }).count,
        creator_user: model.left_joins(:created_by).where.not(created_by_id: nil).where(users: { id: nil }).count,
        creator_account: model.left_joins(:created_by_account).where.not(created_by_account_id: nil).where(accounts: { id: nil }).count
      }
    end
    profiles[:accounts] = Account.left_joins(:user, :person)
      .where("users.id IS NULL OR people.id IS NULL").count
    profiles
  end
end
