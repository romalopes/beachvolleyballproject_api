# frozen_string_literal: true

module MailSender
  DEFAULT_FROM = "BVB Project <romalopes@gmail.com>"
  DEFAULT_REPLY_TO = "romalopes@gmail.com"

  module_function

  def from(env = ENV) = value_for("MAIL_FROM", DEFAULT_FROM, env)
  def reply_to(env = ENV) = value_for("MAIL_REPLY_TO", DEFAULT_REPLY_TO, env)

  def value_for(key, default, env)
    value = env[key].to_s.strip
    value.present? ? value : default
  end
  private_class_method :value_for
end
