require "test_helper"

class EmailVerificationServiceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Verification User",
      email_address: "verify@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  teardown do
    ActionMailer::Base.deliveries.clear
    EmailVerification.define_singleton_method(:require?, @original_require_method) if @original_require_method
  end

  def stub_email_verification_require?(value)
    original = EmailVerification.method(:require?)
    EmailVerification.define_singleton_method(:require?) { value }
    yield
  ensure
    EmailVerification.define_singleton_method(:require?, original)
  end

  test "send_verification generates a token, persists its digest, and enqueues the mailer" do
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      raw_token = EmailVerificationService.send_verification(@user)
      @user.reload
      assert_not_nil raw_token
      assert_not_nil @user.email_verification_token_digest
      assert_not_nil @user.email_verification_sent_at
    end

    assert_equal "Verify your email address for Beach Volleyball Project", ActionMailer::Base.deliveries.last.subject
  end

  test "verify returns the user for a valid token and clears the token digest" do
    raw_token = @user.generate_email_verification_token!

    result = EmailVerificationService.verify(raw_token)

    assert_equal @user, result
    assert result.email_verified?
    assert_nil @user.reload.email_verification_token_digest
  end

  test "verify returns nil for a token that is not tied to any user" do
    assert_nil EmailVerificationService.verify(SecureRandom.urlsafe_base64(32))
  end

  test "verify returns nil for a blank token" do
    assert_nil EmailVerificationService.verify("")
    assert_nil EmailVerificationService.verify(nil)
  end

  test "verify returns nil for a token that has already been consumed" do
    raw_token = @user.generate_email_verification_token!
    EmailVerificationService.verify(raw_token)
    assert_nil EmailVerificationService.verify(raw_token)
  end

  test "verify returns nil for an expired token" do
    raw_token = @user.generate_email_verification_token!
    @user.update!(email_verification_sent_at: 48.hours.ago)
    assert_nil EmailVerificationService.verify(raw_token)
  end

  test "resend does nothing when email verification is disabled in config" do
    stub_email_verification_require?(false) do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        assert_nil EmailVerificationService.resend(@user.email_address)
      end
    end
  end

  test "resend does nothing for a known but already-verified user" do
    stub_email_verification_require?(true) do
      @user.update!(email_verified_at: 1.day.ago)
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        assert_nil EmailVerificationService.resend(@user.email_address)
      end
    end
  end

  test "resend sends a verification email for a pending user and returns the raw token" do
    stub_email_verification_require?(true) do
      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        token = EmailVerificationService.resend(@user.email_address)
        assert_not_nil token
        assert_kind_of String, token
      end
    end
  end

  test "resend does nothing when a resend was made within the cooldown window" do
    stub_email_verification_require?(true) do
      @user.update!(email_verification_sent_at: 30.seconds.ago)

      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        assert_nil EmailVerificationService.resend(@user.email_address)
      end
    end
  end

  test "resend does nothing for an unknown address" do
    stub_email_verification_require?(true) do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        assert_nil EmailVerificationService.resend("nobody@example.com")
      end
    end
  end

  test "resend never raises or reveals whether an address exists to a caller" do
    stub_email_verification_require?(true) do
      assert_nothing_raised do
        EmailVerificationService.resend(@user.email_address)
        EmailVerificationService.resend("nobody@example.com")
      end
    end
  end
end