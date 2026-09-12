module SessionTestHelper
  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end

  def sign_out
    Current.session&.destroy!
    cookies.delete("session_id")
  end

  # Each integration request runs in its own controller instance; Current
  # (a thread-local) is reset between requests. Real browsers re-send the
  # signed cookie, which resume_session picks up — but in tests the cookie
  # jar on `cookies` is NOT automatically carried into the next request's
  # signed jar. Copy the raw cookie value onto the next request's Cookie
  # header so multi-request flows (login -> act -> verify) behave like a
  # browser holding onto its cookie.
  def persist_session_cookie!
    raw = cookies["session_id"]
    return if raw.blank?

    cookie_header = "#{ Rack::Utils.escape("session_id") }=#{ Rack::Utils.escape(raw) }"
    @persisted_cookie_header = cookie_header
    set_cookie_header!
  end

  def set_cookie_header!
    return if @persisted_cookie_header.blank?

    # Merge with any existing Cookie header rather than clobbering it.
    existing = Array(headers["Cookie"])
    headers["Cookie"] = ([@persisted_cookie_header] + existing).uniq.join("; ")
  end

  def clear_persisted_cookie!
    @persisted_cookie_header = nil
    headers["Cookie"] = nil if respond_to?(:headers) && headers
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper

  setup do
    clear_persisted_cookie!
  end

  # Re-attach the persisted cookie before every request issued via the
  # integration DSL (get/post/patch/put/delete/head).
  %i[get post patch put delete head].each do |verb|
    define_method("#{verb}_with_persisted_cookie") do |*args, **kwargs, &block|
      set_cookie_header!
      send("#{verb}_without_persisted_cookie", *args, **kwargs, &block).tap do
        persist_session_cookie!
      end
    end

    alias_method "#{verb}_without_persisted_cookie", verb
    alias_method verb, "#{verb}_with_persisted_cookie"
  end
end
