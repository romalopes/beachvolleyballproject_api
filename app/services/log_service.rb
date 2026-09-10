class LogService
  # Centralized audit logging. Never raises — a logging failure must not break
  # the original request.
  #
  # Usage:
  #   LogService.log(
  #     description: "Created skill \"Jump Serve\"",
  #     user: current_user,
  #     action: "create",
  #     method: request.request_method,
  #     path: request.path,
  #     request_id: request.request_id,
  #     ip_address: request.remote_ip,
  #     user_agent: request.user_agent,
  #     status: response.status,
  #     objects: [skill, category]
  #   )
  def self.log(description:, action:, method:, user: nil, path: nil,
               request_id: nil, ip_address: nil, user_agent: nil,
               status: nil, objects: [])
    return if description.blank? || action.blank? || method.blank?

    ActiveRecord::Base.transaction do
      log = Log.create!(
        description: description,
        action: action,
        method: method,
        user: user,
        path: path,
        request_id: request_id,
        ip_address: ip_address,
        user_agent: user_agent,
        status: status
      )

      Array(objects).compact.each do |object|
        next unless object.respond_to?(:id) && object.id.present?

        LogObject.create!(
          log: log,
          object: object
        )
      end

      log
    end
  rescue StandardError => e
    Rails.logger.error("LogService failed: #{e.message}")
    Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
    nil
  end

  # Generate a human-readable description for a CRUD action on a resource.
  def self.description_for(action, record)
    klass = record.class.name
    label = human_label(record)
    "#{action.capitalize} #{klass} \"#{label}\""
  end

  # Best-effort human-readable label for any record.
  def self.human_label(record)
    if record.respond_to?(:title) && record.title.present?
      record.title.to_s
    elsif record.respond_to?(:name) && record.name.present?
      record.name.to_s
    elsif record.respond_to?(:id)
      "##{record.id}"
    else
      record.to_s
    end
  end
end
