module Impersonation
  extend ActiveSupport::Concern

  included do
    before_action :resume_impersonation
    helper_method :impersonating?, :real_current_user if respond_to?(:helper_method)
  end

  private

  # Effective user for this request. While impersonation is active this is
  # the impersonated user; otherwise the session owner. Mirrors Current.user.
  def current_user
    Current.user
  end

  # Real authenticated user — the admin who logged in. Never impersonated.
  def real_current_user
    Current.real_user
  end

  def impersonating?
    Current.impersonating?
  end

  # Start impersonating +target+ as the currently authenticated admin.
  # Returns true on success, false when not allowed (non-admin real user,
  # nested impersonation, admin/self/unknown target). Callers render the
  # appropriate response; use the controller actions for the full flow.
  def start_impersonating(target)
    return false unless real_current_user&.admin?
    return false if impersonating?
    return false if target.nil? || target == real_current_user || target.admin?

    Current.impersonated_user = target
    session[:impersonated_user_id] = target.id
    if Current.session
      Current.session.update(impersonated_user: target)
    end
    true
  end

  def stop_impersonating
    was_impersonating = impersonating?
    Current.impersonated_user = nil
    session.delete(:impersonated_user_id)
    Current.session&.update(impersonated_user: nil)
    was_impersonating
  end

  # Runs on every request. Re-resolves the impersonated user from session
  # state and validates it, so hand-edited session values can never escalate
  # privileges:
  # - real user must still be an admin (role could have been revoked)
  # - target must exist, must not be an admin, must not be the admin themselves
  # - nested impersonation is impossible (a non-admin real user fails the
  #   admin check, clearing any stale state)
  def resume_impersonation
    Current.impersonated_user = nil
    # Order-independent: callback order varies across controllers because
    # Api::V1::ApplicationController re-declares resume_session (which moves
    # it to the end of the chain). Resolve the session here if it is not
    # populated yet so impersonation state is always restored.
    Current.session ||= find_session_by_cookie || find_session_by_bearer_token
    return unless Current.session

    target_id = session[:impersonated_user_id].presence ||
                Current.session.impersonated_user_id
    return if target_id.nil?

    real = Current.real_user
    target = User.find_by(id: target_id)

    if real&.admin? && target && target != real && !target.admin?
      Current.impersonated_user = target
      # Keep both stores in sync (cookie session vs bearer-token column).
      session[:impersonated_user_id] = target.id
      Current.session.update(impersonated_user: target) if Current.session.impersonated_user_id != target.id
    else
      # Stale or tampered state — clear it everywhere.
      session.delete(:impersonated_user_id)
      Current.session.update(impersonated_user: nil) if Current.session.impersonated_user_id
    end
  end
end
