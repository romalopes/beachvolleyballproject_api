# Prevent profile/person endpoints from becoming a back door for changing an
# organisation's roster. Roster writes use the same owner/administrator
# authority as OrganisationsController; site admins retain their existing
# override. Memberships posted here are still Person-scoped records.
module NestedOrganisationMembershipAuthorization
  private

  def authorize_nested_organisation_memberships!(person:, attributes:)
    attributes = attributes.to_h.with_indifferent_access
    rows = attributes[:organisation_memberships_attributes]
    return true if rows.blank?
    return true if Current.user&.admin?

    actor = Current.user&.person
    return forbidden_nested_membership! if actor.nil?

    rows = rows.is_a?(Array) ? rows : [rows]
    allowed = rows.all? do |row|
      row = row.to_h.with_indifferent_access
      membership = if row[:id].present? && person&.persisted?
                     person.organisation_memberships.find_by(id: row[:id])
                   end
      next false if row[:id].present? && membership.nil?
      removing = ActiveModel::Type::Boolean.new.cast(row[:_destroy])
      next false if removing && membership.present? && !membership.withdrawable?

      organisation_ids = [membership&.organisation_id, row[:organisation_id]].compact_blank.uniq
      organisation_ids.present? &&
        organisation_ids.all? do |organisation_id|
          Organisation.find_by(id: organisation_id)&.manageable_by?(actor)
        end
    end
    return true if allowed

    forbidden_nested_membership!
  end

  def forbidden_nested_membership!
    render json: { errors: ["You must be an owner or administrator of each organisation to change its roster."] },
           status: :forbidden
    false
  end
end
