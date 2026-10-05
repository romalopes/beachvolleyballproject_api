# The claim table was player-profile-only: `player_profile_id` was NOT NULL. The
# unified workflow needs the same pending/approved/rejected/cancelled lifecycle
# for a CoachProfile and for a Person, so the subject becomes polymorphic and the
# legacy column becomes nullable.
#
# Existing rows are backfilled to the polymorphic pair so behaviour is unchanged,
# and the column is retained: a claim carries exactly one of the two, enforced by
# a check constraint, so an existing client reading `player_profile_id` still
# sees the same values.
class AddClaimableToPlayerClaims < ActiveRecord::Migration[8.1]
  def change
    add_reference :player_claims, :claimable, polymorphic: true

    # Relax the legacy column *before* touching it. The backfill below clears it,
    # which cannot happen while it is still NOT NULL.
    change_column_null :player_claims, :player_profile_id, true

    # Normalise every existing claim onto the polymorphic pair, then clear the
    # legacy column. Both steps are required: the constraint below demands
    # *exactly one* subject, so backfilling without clearing would leave every
    # row with two and the migration would fail on any database that already
    # holds claims (it succeeds on an empty one, which is how this slipped
    # through the test suite).
    #
    # The API keeps reporting `player_profile_id` for a PlayerProfile subject —
    # `PlayerClaim#summary` derives it from `claimable_id` — so no client sees a
    # difference.
    execute <<~SQL.squish
      UPDATE player_claims
      SET claimable_type = 'PlayerProfile',
          claimable_id = player_profile_id
      WHERE claimable_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE player_claims
      SET player_profile_id = NULL
      WHERE claimable_id IS NOT NULL
    SQL

    add_check_constraint :player_claims,
                         "(claimable_id IS NOT NULL AND player_profile_id IS NULL) OR " \
                         "(claimable_id IS NULL AND player_profile_id IS NOT NULL)",
                         name: "player_claims_single_subject"

    # The legacy partial index no longer matches anything once the column is
    # cleared, so it is replaced by the polymorphic one.
    remove_index :player_claims, name: "index_player_claims_one_pending_per_profile"

    add_index :player_claims, [ :claimable_type, :claimable_id ], unique: true,
              where: "status = 'pending'", name: "index_player_claims_one_pending_per_claimable"
  end
end
