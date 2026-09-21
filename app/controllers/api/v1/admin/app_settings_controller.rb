module Api
  module V1
    module Admin
      # Admin-only generic CRUD for app_settings rows, backing the "Custom
      # settings" table on the Configuration page.
      #
      # Routes use the setting key as the identifier
      # (e.g. PATCH /api/v1/admin/app_settings/my_key).
      class AppSettingsController < ApplicationController
        before_action :authorize_admin!

        # GET /api/v1/admin/app_settings
        def index
          render json: { settings: AppSetting.ordered_all.map { |s| setting_json(s) } }
        end

        # POST /api/v1/admin/app_settings
        def create
          key = params[:key].to_s.strip
          if key.blank?
            return render json: { error: "Key can't be blank" }, status: :unprocessable_entity
          end
          if AppSetting.exists?(key: key)
            return render json: { error: "Key has already been taken" }, status: :unprocessable_entity
          end

          setting = AppSetting.new(key: key, value: params[:value].to_s)
          if setting.save
            render json: setting_json(setting), status: :created
          else
            render json: { error: setting.errors.full_messages.join(", ") },
                   status: :unprocessable_entity
          end
        end

        # PATCH /api/v1/admin/app_settings/:key
        def update
          setting = AppSetting.find_by(key: params[:key].to_s)
          return render json: { error: "Setting not found" }, status: :not_found if setting.nil?

          if setting.update(value: params[:value].to_s)
            render json: setting_json(setting)
          else
            render json: { error: setting.errors.full_messages.join(", ") },
                   status: :unprocessable_entity
          end
        end

        # DELETE /api/v1/admin/app_settings/:key
        def destroy
          setting = AppSetting.find_by(key: params[:key].to_s)
          return render json: { error: "Setting not found" }, status: :not_found if setting.nil?

          if AppSetting::DEFAULTS.key?(setting.key)
            return render json: { error: "Built-in settings cannot be deleted" },
                          status: :unprocessable_entity
          end

          setting.destroy
          head :no_content
        end

        private

        def setting_json(setting)
          {
            key: setting.key,
            value: setting.value,
            built_in: AppSetting::DEFAULTS.key?(setting.key)
          }
        end
      end
    end
  end
end
