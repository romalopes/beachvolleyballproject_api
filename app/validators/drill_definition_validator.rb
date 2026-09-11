# Domain + schema validator for a Drill's `definition` JSON column.
#
# Schema validation ensures structural correctness (types, enums, required
# fields) against schemas/drill-definition-v1.schema.json. Domain validation
# enforces cross-step business rules (references, movement consistency,
# coordinate bounds) that JSON Schema cannot express.
class DrillDefinitionValidator
  SCHEMA_PATH = Rails.root.join("schemas", "drill-definition-v1.schema.json")

  def initialize(record)
    @record = record
    @definition = record.definition
  end

  def validate
    return if skip?
    return unless hash? || add_type_error

    validate_schema
    validate_domain if @record.errors[:definition].empty?
  end

  private

  def skip?
    @definition.blank? || !@definition.is_a?(Hash) || @definition.empty?
  end

  def hash?
    @definition.is_a?(Hash)
  end

  def add_type_error
    @record.errors.add(:definition, "must be a JSON object")
    false
  end

  def schema
    @schema ||= JSON.parse(File.read(SCHEMA_PATH))
  end

  def validate_schema
    schemer = JSONSchemer.schema(schema)
    schemer.validate(@definition).each do |err|
      pointer = err["pointer"].presence || "root"
      @record.errors.add(:definition, "schema: #{pointer} — #{err['message']}")
    end
  rescue StandardError => e
    @record.errors.add(:definition, "schema validation error: #{e.message}")
  end

  def validate_domain
    check_unique_ids
    check_references
    check_entity_states
    check_coordinate_bounds
    check_movement_consistency
  end

  def entities_by_id
    @entities_by_id ||= {
      participant: @definition["participants"].to_h { |p| [p["id"], p] },
      ball: @definition["balls"].to_h { |b| [b["id"], b] },
      object: @definition["objects"].to_h { |o| [o["id"], o] },
    }
  end

  def check_unique_ids
    %w[participants balls objects].each do |collection|
      ids = @definition[collection].map { |e| e["id"] }
      ids.select { |id| ids.count(id) > 1 }.uniq.each do |dupe|
        @record.errors.add(:definition, "domain: duplicate #{collection.singularize} id '#{dupe}'")
      end
    end
  end

  def check_references
    participant_ids = entities_by_id[:participant].keys.to_set
    ball_ids = entities_by_id[:ball].keys.to_set
    object_ids = entities_by_id[:object].keys.to_set

    each_step do |step|
      step["actions"].each do |a|
        @record.errors.add(:definition, "domain: action references unknown participant '#{a['participant_id']}'") \
          unless participant_ids.include?(a["participant_id"])
      end

      %w[participants balls objects].each do |coll|
        valid_ids = coll == "participants" ? participant_ids : coll == "balls" ? ball_ids : object_ids
        step[coll].each do |state|
          @record.errors.add(:definition, "domain: step '#{step['id']}' #{coll.singularize} '#{state['id']}' is not defined") \
            unless valid_ids.include?(state["id"])
        end
      end

      step["participant_movements"].each do |m|
        @record.errors.add(:definition, "domain: movement references unknown participant '#{m['participant_id']}'") \
          unless participant_ids.include?(m["participant_id"])
      end
      step["ball_movements"].each do |m|
        @record.errors.add(:definition, "domain: movement references unknown ball '#{m['ball_id']}'") \
          unless ball_ids.include?(m["ball_id"])
      end
      step["object_movements"].each do |m|
        @record.errors.add(:definition, "domain: movement references unknown object '#{m['object_id']}'") \
          unless object_ids.include?(m["object_id"])
      end
    end
  end

  def check_entity_states
    each_step do |step|
      %w[participants balls objects].each do |coll|
        ids = step[coll].map { |s| s["id"] }
        ids.select { |id| ids.count(id) > 1 }.uniq.each do |dupe|
          @record.errors.add(:definition, "domain: step '#{step['id']}' has duplicate #{coll.singularize} '#{dupe}'")
        end

        step[coll].each do |state|
          if state["active"]
            @record.errors.add(:definition, "domain: active #{coll.singularize} '#{state['id']}' in step '#{step['id']}' must have a location") \
              if state["location"].nil?
          else
            @record.errors.add(:definition, "domain: inactive #{coll.singularize} '#{state['id']}' in step '#{step['id']}' must not have a location") \
              if state["location"].present?
          end
        end
      end
    end
  end

  def check_coordinate_bounds
    bounds = compute_bounds
    each_step do |step|
      %w[participants balls objects].each do |coll|
        step[coll].each do |state|
          validate_location(state["location"], "#{coll.singularize} '#{state['id']}'", bounds) if state["location"]
        end
      end

      %w[participant_movements ball_movements object_movements].each do |moves|
        step[moves].each do |m|
          validate_location(m["to"], "movement target", bounds)
          validate_location(m["from"], "movement origin", bounds) if m["from"]
        end
      end
    end
  end

  def validate_location(loc, context, bounds)
    court = loc["court"]
    unless bounds[court]
      @record.errors.add(:definition, "domain: #{context} references invalid court '#{court}'")
      return
    end
    b = bounds[court]
    unless loc["x"] >= b[:x_min] && loc["x"] <= b[:x_max]
      @record.errors.add(:definition, "domain: #{context} x=#{loc['x']} out of bounds for #{court} (#{b[:x_min]}..#{b[:x_max]})")
    end
    unless loc["y"] >= b[:y_min] && loc["y"] <= b[:y_max]
      @record.errors.add(:definition, "domain: #{context} y=#{loc['y']} out of bounds for #{court} (#{b[:y_min]}..#{b[:y_max]})")
    end
  end

  # Bounds per court derived from grid + extended_area (spec §11).
  def compute_bounds
    grid = @definition.dig("court", "grid") || { "columns" => 5, "rows" => 4 }
    cols = grid["columns"].to_i
    rows = grid["rows"].to_i
    ext = @definition.dig("court", "extended_area") || {}
    left = ext["left"] ? true : false
    right = ext["right"] ? true : false
    c1 = ext["court_1"] ? true : false
    c2 = ext["court_2"] ? true : false

    x_min = left ? 0 : 1
    x_max = right ? cols + 1 : cols
    {
      "court_1" => { x_min: x_min, x_max: x_max, y_min: c1 ? 0 : 1, y_max: rows },
      "court_2" => { x_min: x_min, x_max: x_max, y_min: 1, y_max: c2 ? rows + 1 : rows },
    }
  end

  def check_movement_consistency
    steps = @definition["steps"]
    steps.each_with_index do |step, idx|
      next_step = steps[idx + 1]
      current_locs = active_locations(step)
      next_locs = next_step ? active_locations(next_step) : {}

      step["participant_movements"].each do |m|
        check_movement(m, "participant_id", current_locs, next_locs, step["id"], next_step&.dig("id"))
      end
      step["ball_movements"].each do |m|
        check_movement(m, "ball_id", current_locs, next_locs, step["id"], next_step&.dig("id"))
      end
      step["object_movements"].each do |m|
        check_movement(m, "object_id", current_locs, next_locs, step["id"], next_step&.dig("id"))
      end
    end
  end

  def active_locations(step)
    locs = {}
    %w[participants balls objects].each do |coll|
      step[coll].each do |state|
        locs[state["id"]] = state["location"] if state["active"] && state["location"]
      end
    end
    locs
  end

  def check_movement(movement, id_key, current_locs, next_locs, step_id, next_step_id)
    id = movement[id_key]

    if movement["from"]
      expected = current_locs[id]
      unless expected && same_location?(movement["from"], expected)
        @record.errors.add(:definition, "domain: movement for '#{id}' in step '#{step_id}' origin does not match current location")
      end
    end

    if next_step_id
      expected_next = next_locs[id]
      unless expected_next && same_location?(movement["to"], expected_next)
        @record.errors.add(:definition, "domain: movement for '#{id}' in step '#{step_id}' target does not match next step location")
      end
    end
  end

  def same_location?(a, b)
    a["court"] == b["court"] && a["x"] == b["x"] && a["y"] == b["y"]
  end

  def each_step
    @definition["steps"].each { |step| yield step }
  end
end

