module RequestLogging
  extend ActiveSupport::Concern

  included do
    after_action :log_request, if: :auditable_request?
  end

  private

  # Only audit meaningful API calls: authenticated mutations and important reads.
  def auditable_request?
    return false unless Current.user
    return true if %w[create update destroy].include?(action_name)

    action_name == "show"
  end

  def log_request
    LogService.log(
      description: request_description,
      action: action_name.downcase,
      method: request.request_method,
      user: Current.user,
      path: request.path,
      request_id: request.request_id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      status: response.status,
      objects: log_objects
    )
  rescue StandardError => e
    Rails.logger.error("RequestLogging failed: #{e.message}")
  end

  def request_description
    records = log_objects
    record = records.first
    return "#{action_name.capitalize} #{controller_name.humanize}" unless record

    LogService.description_for(action_name.downcase, record)
  end

  # Collect the primary resource(s) associated with this request.
  def log_objects
    records = []

    # Standard instance variable pattern: @skill, @drill, @category
    resource_name = controller_name.singularize
    entity = instance_variable_get("@#{resource_name}") rescue nil
    records << entity if entity.present?

    records
  end
end
