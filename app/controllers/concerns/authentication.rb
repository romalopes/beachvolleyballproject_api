module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :resume_session
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options, raise: false
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie || find_session_by_bearer_token
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    # Bearer-token sessions let the JSON API (React SPA) authenticate across
    # origins without relying on cross-site cookies.
    def find_session_by_bearer_token
      token = authorization_bearer_token
      return unless token

      session = Session.find_by(api_token: token)
      return unless session

      if session.api_token_expires_at && session.api_token_expires_at < Time.current
        session.destroy
        return nil
      end
      session
    end

    def authorization_bearer_token
      request.authorization&.match(/\ABearer (.+)\z/)&.captures&.first
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def start_api_session_for(user)
      user.sessions.create!(
        user_agent: request.user_agent,
        ip_address: request.remote_ip,
        api_token: SecureRandom.hex(32),
        api_token_expires_at: 30.days.from_now
      )
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
