# frozen_string_literal: true

require_relative "http_mail_delivery"

class ResendDelivery
  include HttpMailDelivery
  class Error < StandardError; end
  ENDPOINT = URI("https://api.resend.com/emails")

  def initialize(settings)
    @api_key = settings[:api_key]
    @open_timeout = settings[:open_timeout] || DEFAULT_TIMEOUT
    @read_timeout = settings[:read_timeout] || DEFAULT_TIMEOUT
  end

  def deliver!(mail)
    raise Error, "RESEND_API_KEY is not configured" if @api_key.blank?

    post_json(endpoint: ENDPOINT, headers: { "Authorization" => "Bearer #{@api_key}" }, payload: payload_for(mail), error_class: Error, provider: "Resend", open_timeout: @open_timeout, read_timeout: @read_timeout)
    true
  rescue Error
    raise
  rescue StandardError => error
    raise Error, "Resend delivery failed: #{error.class}: #{error.message}"
  end

  def payload_for(mail)
    payload = { from: formatted_address(mail[:from]&.decoded), to: recipient_emails(mail.to), subject: mail.subject.to_s }
    html, text = bodies(mail)
    payload[:html] = html if html.present?
    payload[:text] = text if text.present?
    reply_to = formatted_address(mail[:reply_to]&.decoded)
    payload[:reply_to] = reply_to if reply_to.present?
    payload[:cc] = recipient_emails(mail.cc) if mail.cc.present?
    payload[:bcc] = recipient_emails(mail.bcc) if mail.bcc.present?
    files = attachments(mail)
    payload[:attachments] = files if files.any?
    payload
  end

  private

  def formatted_address(raw)
    address = parse_address(raw)
    return if address.nil?

    address.display_name.present? ? "#{address.display_name} <#{address.address}>" : address.address
  end
end
