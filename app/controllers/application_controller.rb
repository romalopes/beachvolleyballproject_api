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

  # JSON clients (the React SPA) get a 401 instead of an HTML login redirect.
  def request_authentication
    if request.format.json?
      head :unauthorized
    else
      super
    end
  end

  def set_cors_headers
    response.set_header('Access-Control-Allow-Origin', '*')
    response.set_header('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS')
    response.set_header('Access-Control-Allow-Headers', 'Content-Type, Accept')
  end
end


