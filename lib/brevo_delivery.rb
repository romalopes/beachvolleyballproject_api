# frozen_string_literal: true

require_relative "http_mail_delivery"

class BrevoDelivery
  include HttpMailDelivery
  class Error < StandardError; end
  ENDPOINT = URI("https://api.brevo.com/v3/smtp/email")

  def initialize(settings)
    @api_key = settings[:api_key]
    @open_timeout = settings[:open_timeout] || DEFAULT_TIMEOUT
    @read_timeout = settings[:read_timeout] || DEFAULT_TIMEOUT
  end

  def deliver!(mail)
    raise Error, "BREVO_API_KEY is not configured" if @api_key.blank?

    post_json(endpoint: ENDPOINT, headers: { "api-key" => @api_key }, payload: payload_for(mail), error_class: Error, provider: "Brevo", open_timeout: @open_timeout, read_timeout: @read_timeout)
    true
  rescue Error
    raise
  rescue StandardError => error
    raise Error, "Brevo delivery failed: #{error.class}: #{error.message}"
  end

  def payload_for(mail)
    payload = {
      sender: address_payload(mail[:from]&.decoded),
      to: recipient_emails(mail.to).map { |email| { email: email } },
      subject: mail.subject.to_s
    }
    html, text = bodies(mail)
    payload[:htmlContent] = html if html.present?
    payload[:textContent] = text if text.present?
    reply_to = address_payload(mail[:reply_to]&.decoded)
    payload[:replyTo] = reply_to if reply_to.present?
    payload[:cc] = recipient_emails(mail.cc).map { |email| { email: email } } if mail.cc.present?
    payload[:bcc] = recipient_emails(mail.bcc).map { |email| { email: email } } if mail.bcc.present?
    files = attachments(mail).map { |file| { name: file[:filename], content: file[:content] } }
    payload[:attachment] = files if files.any?
    payload
  end

  private

  def address_payload(raw)
    address = parse_address(raw)
    return if address.nil?

    { email: address.address, name: address.display_name.presence }.compact
  end
end
