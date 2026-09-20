# Private test-access gate.
#
# Included in the API base controllers. Every request must carry a valid
# signed test-access token in the X-Test-Access-Token header (see
# TestAccessToken). This is separate from the Authorization header so it never
# interferes with the existing cookie/bearer User sessions (Authentication
# concern) or with devise-jwt in the wine app.
#
# When TEST_ACCESS_PASSWORD is unset the gate is open (disabled) so local
# development and CI are unaffected.
module TestAccess
  extend ActiveSupport::Concern

  TEST_ACCESS_HEADER = "X-Test-Access-Token"

  included do
    before_action :require_test_access
  end

  class_methods do
    # Mirror of Authentication.allow_unauthenticated_access: opt an action out
    # of the test-access gate (health probes, the test-access endpoints…).
    def allow_test_access(**options)
      skip_before_action :require_test_access, **options, raise: false
    end
  end

  private

  def require_test_access
    return unless TestAccessToken.enabled?
    return if test_access_token_valid?

    if request.format.json?
      render json: {
        authenticated: false,
        error: "Test access required",
        code: "test_access_required"
      }, status: :unauthorized
    else
      head :unauthorized
    end
  end

  def test_access_token_valid?
    TestAccessToken.valid?(request.headers[TEST_ACCESS_HEADER])
  end
end
