# Read-only status for the retired Phase 2 data task. Account/profile ownership
# was backfilled by migration 20261006100011 before accounts.person_id was
# removed; repeating that mapping after contract migration is intentionally
# unsupported because the old join key no longer exists.
class AccountIdentityPhase2Backfill
  PROFILE_TYPES = { player_profiles: PlayerProfile, coach_profiles: CoachProfile }.freeze

  def call(dry_run: true)
    raise ArgumentError, "The Account identity backfill is migration-only after Person retirement" unless dry_run

    {
      dry_run: true,
      retired: true,
      message: "Account/profile links were copied by the Person retirement migration; no writes were performed.",
      counts: {
        accounts: Account.count,
        accounts_without_contact_detail: Account.left_joins(:contact_detail).where(contact_details: { id: nil }).count,
        profiles_without_account_link: PROFILE_TYPES.transform_values { |model| model.where(account_id: nil).count },
        profiles_with_legacy_roster_reference: PROFILE_TYPES.transform_values { |model| model.where.not(person_id: nil).count }
      }
    }
  end
end
