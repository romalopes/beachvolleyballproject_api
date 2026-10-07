# Centralized membership-to-capability adapter for organisation authorization.
#
# Organisation membership is contextual authority, not a global login role. Keeping
# the mapping here prevents the model, controllers and nested profile endpoints from
# each re-implementing slightly different interpretations of owner/administrator,
# creator and lifecycle rules.
class OrganisationAccess
  class << self
    # Whether +account+ is an active member of +organisation+.
    #
    # This intentionally checks the exact organisation only. The hierarchy is
    # context, not access: being in a parent federation does not grant access to a
    # child club.
    def active_member?(organisation, account)
      return false unless organisation && account.is_a?(Account)

      organisation.organisation_memberships.active.exists?(account_id: account.id)
    end

    # Roster authority derived from membership only: active owner or active
    # administrator on the exact organisation.
    def manages_membership?(organisation, account)
      return false unless organisation && account.is_a?(Account)

      organisation.organisation_memberships
                  .active
                  .manageable
                  .exists?(account_id: account.id)
    end

    # Record-edit authority derived from membership/creation only. Wider oversight
    # grants (admin/curator) are handled in +can_edit?+ and the controller concern so
    # the distinction between club authority and site oversight remains explicit.
    def edits_record_by_membership?(organisation, account)
      return false unless organisation && account.is_a?(Account)
      return true if manages_membership?(organisation, account)
      return false unless organisation.created_by_account_id == account.id

      active_member?(organisation, account)
    end

    def can_edit?(organisation, user)
      return true if user&.admin? || user&.curator?

      edits_record_by_membership?(organisation, user&.account)
    end

    def can_manage_members?(organisation, user)
      return true if user&.admin?

      manages_membership?(organisation, user&.account)
    end

    def can_read?(organisation, user)
      return true if user&.content_manager?

      active_member?(organisation, user&.account)
    end
  end
end