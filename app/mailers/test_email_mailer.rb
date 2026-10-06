# Controlled one-off email used by the health API send-test-email tool.
#
# The effective transport is embedded in the subject and body so anyone who
# receives the message (or inspects the outbox/file delivery) can see which
# MAIL_TRANSPORT the delivery actually used — even when MAIL_TRANSPORT was
# "auto" and the resolver fell back to another delivery method.
class TestEmailMailer < ApplicationMailer
  # @param to [String] recipient address supplied by the caller
  # @param content [String] plain-text message body supplied by the caller
  # @param transport [String] effective transport name (eg "brevo", "smtp")
  def test_email(to:, content:, transport:, subject: nil)
    @sent_to = to
    @sent_content = content
    @effective_transport = transport

    mail(
      to: to,
      subject: subject.presence || "[Email Test] via #{transport}"
    ) do |format|
      format.html { render plain: test_body_text }
      format.text { render plain: test_body_text }
    end
  end

  private

  def test_body_text
    "This is a health API test email.\n" \
      "Transport used: #{@effective_transport.inspect}\n\n" \
      "#{@sent_content}"
  end

  # ApplicationMailer#mail redirects every message to AppSetting.test_email
  # when test mode is on. That behaviour is for the application's own
  # notifications; this diagnostics send must always reach the address the
  # caller supplied, so the redirect does not apply here.
  def mail(headers = {}, &block)
    if AppSetting.test?
      headers[:subject] = "[TEST] #{headers[:subject]}"
    end
    super
  end
end
