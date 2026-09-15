# Definitions written before the `court` → `side` rename (#99) still carry the
# old vocabulary: a top-level `court` instead of `side`, and locations whose
# `court` value is `"court_1"` / `"court_2"`. They fail the v1 schema, so the
# viewer silently fell back to its sample and the editor could not render their
# real coordinates. Rewrite them in place — the rename is unambiguous: no v1
# key or enum value contains `court`.
class MigrateLegacyCourtDefinitionsToSide < ActiveRecord::Migration[8.1]
  # Explicitly require the validator for the post-conversion check, mirroring
  # what Drill does (app/validators was added after the server booted).
  require Rails.root.join("app/validators/drill_definition_validator")

  # Minimal local model: migrations must not depend on app model internals.
  class LegacyDrill < ActiveRecord::Base
    self.table_name = "drills"
  end

  def up
    LegacyDrill.reset_column_information

    migrated = []
    LegacyDrill.find_each do |drill|
      converted = convert(drill.definition)
      next if converted.nil?

      drill.update_columns(definition: converted)
      migrated << drill.slug
      warn_if_still_invalid(drill, converted)
    end

    say "Converted #{migrated.size} legacy definition(s)#{migrated.any? ? ": #{migrated.join(', ')}" : ""}.", true
  end

  def down
    # One-off data repair: restoring the pre-`side` shape would only re-break
    # these rows, so there is nothing to revert.
    say "Nothing to revert: legacy `court` keys are replaced by `side`.", true
  end

  private

  # The rewritten definition, or nil when the row needs no conversion.
  def convert(definition)
    return nil unless definition.is_a?(Hash)
    return nil unless legacy?(definition)

    convert_value(definition)
  end

  def legacy?(value)
    case value
    when Hash then value.any? { |key, nested| key == "court" || legacy?(nested) }
    when Array then value.any? { |item| legacy?(item) }
    when String then value.start_with?("court_")
    else false
    end
  end

  def convert_value(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), converted|
        converted[key == "court" ? "side" : key] = convert_value(nested)
      end
    when Array
      value.map { |item| convert_value(item) }
    when String
      value.start_with?("court_") ? value.sub("court_", "side_") : value
    else
      value
    end
  end

  # Surfaces (rather than swallows) any row the conversion did not fully fix.
  def warn_if_still_invalid(drill, definition)
    probe = LegacyDrill.new(definition: definition)
    DrillDefinitionValidator.new(probe).validate
    return if probe.errors[:definition].empty?

    say "WARNING: #{drill.slug} (#{drill.id}) still fails validation: #{probe.errors[:definition].join('; ')}", true
  end
end
