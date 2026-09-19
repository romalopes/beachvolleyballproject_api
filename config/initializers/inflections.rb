# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

ActiveSupport::Inflector.inflections(:en) do |inflect|
  # The plural used by the training_focuses table. Without this rule the
  # inflector singularizes "focuses" to "focuse", which breaks association
  # reflection (e.g. TrainingSession#training_focuses, inverse_of lookups).
  inflect.irregular "focus", "focuses"

  # Brand casing for the video providers. Without these rules Zeitwerk inflects
  # youtube.rb -> Youtube / tiktok.rb -> Tiktok, which never matches the
  # VideoProviders::YouTube / ::TikTok class names.
  inflect.acronym "YouTube"
  inflect.acronym "TikTok"
end
