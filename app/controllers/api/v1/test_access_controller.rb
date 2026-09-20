module Api
  module V1
    # Private test-access endpoints.
    #
    # POST /api/v1/test_access — validates the configured password and issues
    #   a signed, expiring token ({ authenticated: true, token, expires_at }).
    #   A wrong password is a 401 with no hint about the configured value.
    # GET  /api/v1/test_access — verifies the token sent in the
    #   X-Test-Access-Token header; the SPA calls this on boot to detect an
    #   expired credential.
    class TestAccessController < ApplicationController
      allow_test_access only: %i[create show]

      # Brute-force protection for the password check (Rails 8 built-in,
      # backed by the Solid Cache store in production).
      rate_limit to: 10, within: 1.minute, only: :create

      def create
        unless TestAccessToken.enabled?
          return render json: { authenticated: true, token: nil, disabled: true }
        end

        if TestAccessToken.matches?(params[:password])
          render json: {
            authenticated: true,
            token: TestAccessToken.generate,
            expires_at: TestAccessToken.expiration.from_now.utc.iso8601
          }
        else
          render json: { authenticated: false, error: "Invalid password" },
                 status: :unauthorized
        end
      end

      def show
        if TestAccessToken.valid?(request.headers[TestAccess::TEST_ACCESS_HEADER])
          render json: { authenticated: true }
        else
          render json: {
            authenticated: false,
            error: "Invalid or expired test access token",
            code: "test_access_required"
          }, status: :unauthorized
        end
      end
    end
  end
end
