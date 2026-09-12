class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :impersonated_user

  # Effective user: the impersonated user while impersonation is active,
  # otherwise the owner of the session. All existing `Current.user` callers
  # (ownership, content auth, account scoping) automatically operate on the
  # effective user.
  def user
    impersonated_user || session&.user
  end

  # Real authenticated user — the admin who logged in. Never affected by
  # impersonation; used for admin authorization and audit logging.
  def real_user
    session&.user
  end

  def impersonating?
    !impersonated_user.nil?
  end
end
