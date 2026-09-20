module Api
  module V1
    # Base controller for the JSON API. All Api::V1::*Controller classes that
    # declare `ApplicationController` resolve to this class via constant lookup.
    class ApplicationController < ::ApplicationController
      # JSON API consumers (the React SPA) authenticate with cookie sessions but
      # do not carry CSRF tokens; null_session would drop cookies on unverified
      # POSTs. JSON POSTs are protected cross-origin by CORS anyway.
      skip_forgery_protection

      # Public API — no User authentication required to browse data.
      skip_before_action :require_authentication, raise: false

      # Private test-access gate: while TEST_ACCESS_PASSWORD is configured,
      # every API request must carry a valid signed test-access token (see
      # TestAccess / TestAccessToken). Independent of User authentication.
      include TestAccess

      # Always populate Current.session from the cookie so authorization helpers
      # (admin?/coach?/owner checks) work even when authentication is optional.
      before_action :resume_session
    end
  end
end
