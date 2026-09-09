class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Skip CSRF for API requests (JSON)
  protect_from_forgery with: :null_session, if: -> { request.format.json? }

  # CORS headers for API access
  before_action :set_cors_headers

  private

  # Authorization helpers
  def authorize_admin!
    return if Current.user&.admin?

    if Current.user.nil?
      if request.format.json?
        head :unauthorized
      else
        redirect_to new_session_path, alert: "Please sign in."
      end
    elsif request.format.json?
      render json: { error: "Forbidden" }, status: :forbidden
    else
      redirect_to root_path, alert: "You are not authorized to perform this action."
    end
  end

  def authorize_owner_or_admin!(owner)
    return if Current.user&.admin? || Current.user == owner

    render_unauthorized_or_forbidden
  end

  # JSON clients (the React SPA) get a 401 instead of an HTML login redirect.
  def request_authentication
    if request.format.json?
      head :unauthorized
    else
      super
    end
  end

  private

  def render_unauthorized_or_forbidden
    if Current.user.nil?
      if request.format.json?
        head :unauthorized
      else
        redirect_to new_session_path, alert: "Please sign in."
      end
    elsif request.format.json?
      render json: { error: "Forbidden" }, status: :forbidden
    else
      redirect_to root_path, alert: "You are not authorized to perform this action."
    end
  end

  def set_cors_headers
    response.set_header("Access-Control-Allow-Origin", "*")
    response.set_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Content-Type, Accept, Authorization")
  end
end
