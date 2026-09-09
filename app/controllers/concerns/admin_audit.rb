module AdminAudit
  extend ActiveSupport::Concern

  included do
    after_action :log_admin_action, only: [:create, :update, :destroy]
  end

  private

  def log_admin_action
    action = case action_name
             when "create" then "create"
             when "update" then "update"
             when "destroy" then "destroy"
             end

    return unless action

    user = Current.user || Current.session&.user
    return unless user

    entity = instance_variable_get("@#{controller_name.singularize}") rescue nil
    if action == "destroy"
      # `destroy` removes the record from the DB, so log even though it is no
      # longer persisted. Fall back to params when the ivar is unavailable.
      entity_id = entity&.id || params[:id]
      AdminActivity.create!(
        user: user,
        action: action,
        entity_type: entity&.class&.name || controller_name.singularize.classify,
        entity_id: entity_id,
        entity_label: entity ? entity_label(entity) : entity_id.to_s,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
      return
    end

    # Only log persisted entities (a failed create has no id yet).
    return unless entity.present? && entity.persisted?

    AdminActivity.create!(
      user: user,
      action: action,
      entity_type: entity.class.name,
      entity_id: entity.id,
      entity_label: entity_label(entity),
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished,
         ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
    # Don't let audit failures break admin CRUD.
  end

  def entity_label(entity)
    if entity.respond_to?(:title)
      entity.title.to_s
    elsif entity.respond_to?(:name)
      entity.name.to_s
    else
      entity.to_s
    end
  end
end

