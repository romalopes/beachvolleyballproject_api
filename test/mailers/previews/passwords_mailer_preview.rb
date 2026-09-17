# Preview all emails at http://localhost:3000/rails/mailers/passwords_mailer
class PasswordsMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/passwords_mailer/reset_password_instructions
  def reset_password_instructions
    PasswordsMailer.reset_password_instructions(User.take)
  end
end
