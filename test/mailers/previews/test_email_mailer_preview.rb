# Preview all emails at /rails/mailers/test_email_mailer/test_email
class TestEmailMailerPreview < ActionMailer::Preview
  def test_email
    TestEmailMailer.test_email(
      to: "recipient@example.com",
      content: "Body preview for the health API send-test-email tool.",
      transport: "file"
    )
  end
end
