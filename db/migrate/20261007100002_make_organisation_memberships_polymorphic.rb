# frozen_string_literal: true

# Adds an explicit membership subject without rewriting the applied historical
# Person migration. Account rows are backfilled first; profiles can then be
# members in their own right until a successful claim promotes them to Account.
class MakeOrganisationMembershipsPolymorphic < ActiveRecord::Migration[8.1]
  def up
    add_reference :organisation_memberships, :memberable, polymorphic: true
    execute <<~SQL
      UPDATE organisation_memberships
      SET memberable_type = 'Account', memberable_id = account_id
      WHERE account_id IS NOT NULL
    SQL
    change_column_null :organisation_memberships, :memberable_type, false
    change_column_null :organisation_memberships, :memberable_id, false
    add_index :organisation_memberships, %i[organisation_id memberable_type memberable_id],
      unique: true, name: "index_organisation_memberships_on_subject"
  end

  def down
    remove_index :organisation_memberships, name: "index_organisation_memberships_on_subject"
    remove_reference :organisation_memberships, :memberable, polymorphic: true
  end
end
