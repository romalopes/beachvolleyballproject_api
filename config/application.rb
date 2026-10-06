require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative "../lib/http_mail_delivery"
require_relative "../lib/brevo_delivery"
require_relative "../lib/resend_delivery"
require_relative "../lib/mail_transport"
require_relative "../lib/mail_sender"

module BeachvolleyballprojectApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Application version surfaced by GET /api/v1/health and
    # /api/v1/health/detailed. Kept on the Application config object so it is
    # always present at request time, independent of initializer/eager-load
    # ordering. The React app mirrors this in
    # beachvolleyballproject/src/constants/versions.ts (APP_VERSION) and the
    # "Backend Version Matches APP_VERSION" health check flags drift.
    config.health_version = ENV["APP_VERSION"].presence || "0.0.21"

    initializer "email_delivery.transport", after: "action_mailer.set_configs" do
      ActionMailer::Base.add_delivery_method(:brevo, BrevoDelivery, open_timeout: 10, read_timeout: 10)
      ActionMailer::Base.add_delivery_method(:resend, ResendDelivery, open_timeout: 10, read_timeout: 10)
      next if Rails.env.test?

      case MailTransport.resolve(ENV, logger: Rails.logger)
      when "brevo"
        ActionMailer::Base.delivery_method = :brevo
        ActionMailer::Base.brevo_settings = { api_key: ENV["BREVO_API_KEY"], open_timeout: 10, read_timeout: 10 }
      when "resend"
        ActionMailer::Base.delivery_method = :resend
        ActionMailer::Base.resend_settings = { api_key: ENV["RESEND_API_KEY"], open_timeout: 10, read_timeout: 10 }
      when "smtp"
        ActionMailer::Base.delivery_method = :smtp
      when "file"
        ActionMailer::Base.delivery_method = :file
        ActionMailer::Base.file_settings = { location: Rails.root.join("tmp/mails") }
      end
    end
  end
end
