class PasswordsMailer < ApplicationMailer
  def reset_password_instructions(user)
    @user = user
    mail subject: "Reset your password", to: user.email_address
  end
end
