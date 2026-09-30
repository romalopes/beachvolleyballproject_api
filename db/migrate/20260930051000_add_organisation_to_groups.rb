# Give a Group its organisation.
#
# The group is "a group of people who share an Organisation", and this is where
# that is actually recorded. Without it the rule was unverifiable: nothing could
# check on a later edit that the members still share anything, and the member
# picker had no single correct answer to filter on.
#
# Nullable on purpose, with no backfill. The old schema recorded no organisation
# on a group at all, and it cannot be inferred from the members — the development
# data's one group has members spread across four organisations, so inference
# would have invented an answer. Existing groups are left NULL for somebody who
# actually knows to place them; requiring NOT NULL would have blocked this
# migration outright on data with no derivable value.
class AddOrganisationToGroups < ActiveRecord::Migration[8.1]
  def up
    add_reference :groups, :organisation, null: true, foreign_key: true

    undecided = select_value("SELECT COUNT(*) FROM groups WHERE organisation_id IS NULL").to_i
    say "#{undecided} group(s) left without an organisation; an administrator must place them"
  end

  def down
    remove_reference :groups, :organisation
  end
end
