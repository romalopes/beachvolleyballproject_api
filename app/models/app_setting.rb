# Global application configuration, backed by the app_settings table.
#
# Each setting is a key/value string pair; typed accessors coerce values and
# fall back to defaults when a key has never been set. This keeps feature
# toggles persistable at runtime by admins via the Configuration page
# instead of redeploying.
#
# Settings:
#   "logs_enabled"   — when false, LogService skips persisting audit logs
#                      to the database (file/Rails logs are unaffected).
#                      Exposed as "logs_saved_to_database" in the API.
#   "test"           — when true, every saved audit log triggers an email
#                      notification to the address defined in "test_email".
#   "test_email"     — the recipient address for test-mode notifications.
class AppSetting < ApplicationRecord
  # Defaults used when a key has never been persisted.
  DEFAULTS = {
    "logs_enabled" => true,
    "test" => false,
    "test_email" => "romalopes@yahoo.com.br"
  }.freeze

  validates :key, presence: true, uniqueness: true

  # All persisted settings plus built-in defaults that have never been set,
  # ordered by key. Custom rows (no default) read back as "" when missing,
  # so the "Add setting" UI can create them.
  def self.ordered_all
    persisted = order(:key).to_a
    missing = DEFAULTS.keys.reject { |key| persisted.any? { |s| s.key == key } }
    (persisted + missing.map { |key| new(key: key, value: DEFAULTS.fetch(key).to_s) })
      .sort_by(&:key)
  end

  # Audit-trail master switch: when false, LogService skips persisting
  # Log/LogObject rows entirely (file logs are unaffected).
  def self.logs_enabled?
    boolean("logs_enabled")
  end

  # Test-mode toggle: when true, every saved audit log triggers an email
  # notification to AppSetting.test_email.
  def self.test?
    boolean("test")
  end

  # Recipient address for test-mode email notifications.
  def self.test_email
    string("test_email")
  end

  def self.set!(key, value)
    setting = find_or_initialize_by(key: key.to_s)
    setting.value = value.to_s
    setting.save!
    value
  end

  # Coerces the stored string into a boolean. Accepts booleans as-is so the
  # controller can pass params straight through. A missing row falls back to
  # the default rather than nil (nil would read as "disabled").
  def self.boolean(key)
    raw = find_by(key: key.to_s)&.value
    return DEFAULTS.fetch(key.to_s) if raw.nil?
    return raw unless raw.is_a?(String)

    ActiveModel::Type::Boolean.new.cast(raw)
  rescue ActiveRecord::StatementInvalid
    # Table may not exist yet (e.g. mid-migration boot); default safely.
    DEFAULTS[key.to_s]
  end

  # Returns the stored string value, falling back to the default when the
  # key (or its value) is missing.
  def self.string(key)
    raw = find_by(key: key.to_s)&.value
    return DEFAULTS.fetch(key.to_s) if raw.nil?

    raw
  rescue ActiveRecord::StatementInvalid
    # Table may not exist yet (e.g. mid-migration boot); default safely.
    DEFAULTS[key.to_s]
  end
end
