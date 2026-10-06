# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "uri"

module HttpMailDelivery
  DEFAULT_TIMEOUT = 10

  def parse_address(raw)
    return if raw.to_s.strip.blank?

    address = Mail::Address.new(raw)
    address if address.address.present?
  end

  def recipient_emails(addresses) = Array(addresses).filter_map { |email| email.to_s.strip.presence }

  def bodies(mail)
    return [mail.html_part&.body&.decoded, mail.text_part&.body&.decoded] if mail.multipart?

    mail.content_type.to_s.include?("text/html") ? [mail.body.decoded, nil] : [nil, mail.body.decoded]
  end

  def attachments(mail)
    mail.attachments.map { |attachment| { filename: attachment.filename, content: Base64.strict_encode64(attachment.body.decoded) } }
  end

  def post_json(endpoint:, headers:, payload:, error_class:, provider:, open_timeout:, read_timeout:)
    request = Net::HTTP::Post.new(endpoint)
    request["Content-Type"] = "application/json"
    headers.each { |name, value| request[name] = value }
    request.body = JSON.generate(payload)
    response = Net::HTTP.start(endpoint.host, endpoint.port, use_ssl: true, open_timeout: open_timeout, read_timeout: read_timeout) { |http| http.request(request) }
    return response if response.is_a?(Net::HTTPSuccess)

    body = response.body.to_s.truncate(1_000)
    raise error_class, "#{provider} API responded #{response.code}: #{body}"
  end
end
