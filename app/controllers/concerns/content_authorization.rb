module ContentAuthorization
  extend ActiveSupport::Concern

  private

  # Coaches and admins may create content.
  def require_content_creator!
    return if Current.user&.coach? || Current.user&.admin?

    render_unauthorized_or_forbidden
  end

  # Owners and admins may modify/delete content.
  def authorize_content_owner!(owner)
    return if Current.user&.admin? || Current.user == owner

    render_unauthorized_or_forbidden
  end
end
