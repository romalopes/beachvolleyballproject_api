module ContentAuthorization
  extend ActiveSupport::Concern

  private

  # Coaches and admins may create content.
  def require_content_creator!
    return if Current.user&.coach? || Current.user&.admin?

    render_unauthorized_or_forbidden
  end

  # Trainings are shared resources managed by coaches, curators and admins.
  # This is deliberately NOT keyed off `training_session.created_by_id`: a
  # session created yesterday by one coach must stay manageable by the other
  # coaches, curators and admins responsible for the shared schedule.
  def require_training_manager!
    return if Current.user&.content_manager?

    render_unauthorized_or_forbidden
  end

  # Owners and admins may modify/delete content.
  def authorize_content_owner!(owner)
    return if Current.user&.admin? || Current.user == owner

    render_unauthorized_or_forbidden
  end
end
