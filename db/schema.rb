# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_28_000004) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_addresses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "postal_code"
    t.string "state"
    t.string "street_address"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_account_addresses_on_account_id", unique: true
  end

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "person_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["person_id"], name: "index_accounts_on_person_id", unique: true
    t.index ["user_id"], name: "index_accounts_on_user_id", unique: true
  end

  create_table "admin_activities", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "entity_label"
    t.string "entity_type", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["action", "created_at"], name: "index_admin_activities_on_action_and_created_at"
    t.index ["entity_type", "entity_id"], name: "index_admin_activities_on_entity_type_and_entity_id"
    t.index ["user_id"], name: "index_admin_activities_on_user_id"
  end

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "assessment_categories", force: :cascade do |t|
    t.bigint "assessment_definition_id", null: false
    t.bigint "category_custom_id"
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "weight", null: false
    t.index ["assessment_definition_id", "category_custom_id"], name: "index_assessment_categories_on_definition_and_custom", unique: true, where: "(category_custom_id IS NOT NULL)"
    t.index ["assessment_definition_id", "category_id"], name: "index_assessment_categories_on_definition_and_category", unique: true, where: "(category_id IS NOT NULL)"
    t.index ["assessment_definition_id"], name: "index_assessment_categories_on_assessment_definition_id"
    t.index ["category_custom_id"], name: "index_assessment_categories_on_category_custom_id"
    t.index ["category_id"], name: "index_assessment_categories_on_category_id"
    t.check_constraint "\"position\" >= 0", name: "assessment_categories_position_non_negative"
    t.check_constraint "category_id IS NOT NULL AND category_custom_id IS NULL OR category_id IS NULL AND category_custom_id IS NOT NULL", name: "assessment_categories_source_xor"
    t.check_constraint "weight > 0", name: "assessment_categories_weight_positive"
  end

  create_table "assessment_category_scores", force: :cascade do |t|
    t.bigint "assessment_category_id", null: false
    t.bigint "assessment_id", null: false
    t.datetime "created_at", null: false
    t.bigint "criterion_id"
    t.text "notes"
    t.integer "reported_value"
    t.string "scale", default: "one_to_ten", null: false
    t.integer "score"
    t.datetime "updated_at", null: false
    t.index ["assessment_category_id"], name: "index_assessment_category_scores_on_assessment_category_id"
    t.index ["assessment_id", "assessment_category_id", "criterion_id"], name: "index_assessment_category_scores_on_category_and_criterion", unique: true, where: "(criterion_id IS NOT NULL)"
    t.index ["assessment_id", "assessment_category_id"], name: "index_assessment_category_scores_on_assessment_and_category", unique: true, where: "(criterion_id IS NULL)"
    t.index ["assessment_id"], name: "index_assessment_category_scores_on_assessment_id"
    t.index ["criterion_id"], name: "index_assessment_category_scores_on_criterion_id"
    t.check_constraint "(score IS NULL) = (reported_value IS NULL)", name: "assessment_category_scores_score_pair"
    t.check_constraint "scale::text = ANY (ARRAY['one_to_five'::character varying::text, 'one_to_ten'::character varying::text, 'one_to_hundred'::character varying::text])", name: "assessment_category_scores_scale"
    t.check_constraint "score IS NULL OR score >= 0 AND score <= 100", name: "assessment_category_scores_score_range"
  end

  create_table "assessment_definitions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description"
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_assessment_definitions_on_created_by_id"
    t.index ["name"], name: "index_assessment_definitions_on_name"
    t.index ["status"], name: "index_assessment_definitions_on_status"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'active'::character varying::text, 'archived'::character varying::text])", name: "assessment_definitions_status"
  end

  create_table "assessment_session_participants", force: :cascade do |t|
    t.bigint "assessment_session_id", null: false
    t.datetime "created_at", null: false
    t.string "inclusion", default: "included", null: false
    t.string "missing_reason"
    t.bigint "player_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assessment_session_id", "player_profile_id"], name: "index_session_participants_on_session_and_player", unique: true
    t.index ["assessment_session_id"], name: "index_assessment_session_participants_on_assessment_session_id"
    t.index ["player_profile_id"], name: "index_assessment_session_participants_on_player_profile_id"
    t.check_constraint "inclusion::text = ANY (ARRAY['included'::character varying::text, 'excluded'::character varying::text])", name: "assessment_session_participants_inclusion"
  end

  create_table "assessment_sessions", force: :cascade do |t|
    t.bigint "assessment_definition_id", null: false
    t.bigint "coach_profile_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "group_id"
    t.string "name"
    t.text "notes"
    t.datetime "published_at"
    t.date "scheduled_on"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["assessment_definition_id"], name: "index_assessment_sessions_on_assessment_definition_id"
    t.index ["coach_profile_id"], name: "index_assessment_sessions_on_coach_profile_id"
    t.index ["created_by_id"], name: "index_assessment_sessions_on_created_by_id"
    t.index ["group_id"], name: "index_assessment_sessions_on_group_id"
    t.index ["scheduled_on"], name: "index_assessment_sessions_on_scheduled_on"
    t.index ["status"], name: "index_assessment_sessions_on_status"
    t.check_constraint "status::text <> 'published'::text OR published_at IS NOT NULL", name: "assessment_sessions_published_requires_timestamp"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'withdrawn'::character varying::text])", name: "assessment_sessions_status"
  end

  create_table "assessments", force: :cascade do |t|
    t.bigint "assessment_definition_id"
    t.bigint "assessment_session_id"
    t.bigint "category_id"
    t.bigint "coach_profile_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "custom_category"
    t.text "notes"
    t.bigint "player_profile_id", null: false
    t.integer "reported_value"
    t.string "scale", default: "one_to_ten"
    t.integer "score"
    t.string "status", default: "draft", null: false
    t.bigint "training_session_id"
    t.datetime "updated_at", null: false
    t.index ["assessment_definition_id"], name: "index_assessments_on_assessment_definition_id"
    t.index ["assessment_session_id"], name: "index_assessments_on_assessment_session_id"
    t.index ["category_id"], name: "index_assessments_on_category_id"
    t.index ["coach_profile_id"], name: "index_assessments_on_coach_profile_id"
    t.index ["created_by_id"], name: "index_assessments_on_created_by_id"
    t.index ["player_profile_id", "created_at"], name: "index_assessments_on_player_profile_id_and_created_at"
    t.index ["player_profile_id"], name: "index_assessments_on_player_profile_id"
    t.index ["status"], name: "index_assessments_on_status"
    t.index ["training_session_id"], name: "index_assessments_on_training_session_id"
    t.check_constraint "assessment_definition_id IS NOT NULL OR (score IS NULL) = (reported_value IS NULL)", name: "assessments_score_pair"
    t.check_constraint "assessment_definition_id IS NOT NULL OR category_id IS NOT NULL AND custom_category IS NULL OR category_id IS NULL AND custom_category IS NOT NULL", name: "assessments_category_xor_custom_category"
    t.check_constraint "assessment_definition_id IS NULL OR category_id IS NULL AND custom_category IS NULL", name: "assessment_definition_xor_rubric"
    t.check_constraint "score IS NULL OR score >= 0 AND score <= 100", name: "assessments_score_range"
    t.check_constraint "status::text = 'draft'::text OR score IS NOT NULL AND (assessment_definition_id IS NOT NULL OR reported_value IS NOT NULL)", name: "assessments_published_requires_score"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'active'::character varying::text, 'withdrawn'::character varying::text])", name: "assessments_status"
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "category_customs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "shared", null: false
    t.index ["created_by_id", "name"], name: "index_category_customs_on_creator_and_name", unique: true
    t.index ["created_by_id"], name: "index_category_customs_on_created_by_id"
    t.index ["visibility"], name: "index_category_customs_on_visibility"
    t.check_constraint "visibility::text = ANY (ARRAY['shared'::character varying::text, 'private'::character varying::text])", name: "category_customs_visibility"
  end

  create_table "coach_profiles", force: :cascade do |t|
    t.string "coaching_level"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "person_id", null: false
    t.text "qualifications"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "shared", null: false
    t.index ["created_by_id"], name: "index_coach_profiles_on_created_by_id"
    t.index ["person_id"], name: "index_coach_profiles_on_person_id", unique: true
    t.index ["status"], name: "index_coach_profiles_on_status"
    t.index ["visibility"], name: "index_coach_profiles_on_visibility"
  end

  create_table "criteria", force: :cascade do |t|
    t.bigint "assessment_category_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["assessment_category_id", "name"], name: "index_criteria_on_assessment_category_id_and_name", unique: true
    t.index ["assessment_category_id", "position"], name: "index_criteria_on_assessment_category_id_and_position"
    t.index ["assessment_category_id"], name: "index_criteria_on_assessment_category_id"
    t.check_constraint "\"position\" >= 0", name: "criteria_position_non_negative"
  end

  create_table "drill_skills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "drill_id", null: false
    t.bigint "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["drill_id", "skill_id"], name: "index_drill_skills_on_drill_id_and_skill_id", unique: true
    t.index ["skill_id"], name: "index_drill_skills_on_skill_id"
  end

  create_table "drills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.jsonb "definition", default: {}, null: false
    t.string "difficulty_level"
    t.integer "ideal_num_players"
    t.integer "max_players"
    t.integer "min_players"
    t.text "setup_instructions"
    t.string "slug"
    t.string "title"
    t.string "training_stage"
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_drills_on_created_by_id"
    t.index ["slug"], name: "index_drills_on_slug", unique: true
    t.index ["training_stage"], name: "index_drills_on_training_stage"
    t.check_constraint "difficulty_level IS NULL OR (difficulty_level::text = ANY (ARRAY['beginner'::character varying::text, 'intermediate'::character varying::text, 'advanced'::character varying::text]))", name: "drills_difficulty_level_check"
    t.check_constraint "ideal_num_players IS NULL OR min_players IS NULL OR max_players IS NULL OR ideal_num_players >= min_players AND ideal_num_players <= max_players", name: "drills_ideal_players_check"
    t.check_constraint "min_players IS NULL OR max_players IS NULL OR min_players <= max_players", name: "drills_player_range_check"
    t.check_constraint "training_stage IS NULL OR (training_stage::text = ANY (ARRAY['warmup'::character varying::text, 'beginning'::character varying::text, 'middle'::character varying::text, 'end'::character varying::text]))", name: "drills_training_stage_check"
  end

  create_table "group_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "group_id", null: false
    t.bigint "player_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id", "player_profile_id"], name: "index_group_memberships_on_group_and_player", unique: true
    t.index ["group_id"], name: "index_group_memberships_on_group_id"
    t.index ["player_profile_id"], name: "index_group_memberships_on_player_profile_id"
  end

  create_table "groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "shared", null: false
    t.index "lower((name)::text)", name: "index_groups_on_lower_name", unique: true
    t.index ["created_by_id"], name: "index_groups_on_created_by_id"
    t.index ["name"], name: "index_groups_on_name"
    t.index ["slug"], name: "index_groups_on_slug", unique: true
    t.index ["status"], name: "index_groups_on_status"
    t.index ["visibility"], name: "index_groups_on_visibility"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'archived'::character varying::text])", name: "groups_status"
    t.check_constraint "visibility::text = ANY (ARRAY['shared'::character varying::text, 'private'::character varying::text])", name: "groups_visibility"
  end

  create_table "log_objects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "log_id", null: false
    t.bigint "object_id", null: false
    t.string "object_type", null: false
    t.datetime "updated_at", null: false
    t.index ["log_id"], name: "index_log_objects_on_log_id"
    t.index ["object_type", "object_id"], name: "index_log_objects_on_object"
    t.index ["object_type", "object_id"], name: "index_log_objects_on_object_type_and_object_id"
  end

  create_table "logs", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.string "ip_address"
    t.string "method", null: false
    t.string "path"
    t.string "request_id"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id"
    t.index ["action", "created_at"], name: "index_logs_on_action_and_created_at"
    t.index ["created_at"], name: "index_logs_on_created_at"
    t.index ["request_id"], name: "index_logs_on_request_id"
    t.index ["user_id", "created_at"], name: "index_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_logs_on_user_id"
  end

  create_table "people", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "creation_source", default: "system", null: false
    t.date "date_of_birth"
    t.string "email"
    t.string "first_name", null: false
    t.string "last_name"
    t.bigint "merged_into_id"
    t.string "phone"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_people_on_created_by_id"
    t.index ["creation_source"], name: "index_people_on_creation_source"
    t.index ["email"], name: "index_people_on_email"
    t.index ["merged_into_id"], name: "index_people_on_merged_into_id"
    t.index ["status"], name: "index_people_on_status"
  end

  create_table "person_aliases", force: :cascade do |t|
    t.string "alias_type"
    t.datetime "created_at", null: false
    t.string "full_name", null: false
    t.bigint "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["full_name"], name: "index_person_aliases_on_full_name"
    t.index ["person_id"], name: "index_person_aliases_on_person_id"
  end

  create_table "player_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "level"
    t.bigint "person_id", null: false
    t.string "preferred_position"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "shared", null: false
    t.index ["created_by_id"], name: "index_player_profiles_on_created_by_id"
    t.index ["person_id"], name: "index_player_profiles_on_person_id", unique: true
    t.index ["status"], name: "index_player_profiles_on_status"
    t.index ["visibility"], name: "index_player_profiles_on_visibility"
  end

  create_table "ranking_consolidation_rows", force: :cascade do |t|
    t.integer "average_score"
    t.jsonb "coach_scores", default: {}, null: false
    t.integer "coverage", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "player_profile_id", null: false
    t.integer "rank"
    t.bigint "ranking_consolidation_id", null: false
    t.datetime "updated_at", null: false
    t.index ["player_profile_id"], name: "index_ranking_consolidation_rows_on_player_profile_id"
    t.index ["ranking_consolidation_id", "player_profile_id"], name: "index_consolidation_rows_on_consolidation_and_player", unique: true
    t.index ["ranking_consolidation_id"], name: "index_ranking_consolidation_rows_on_ranking_consolidation_id"
  end

  create_table "ranking_consolidation_sessions", force: :cascade do |t|
    t.bigint "assessment_session_id", null: false
    t.datetime "created_at", null: false
    t.boolean "excluded_from_snapshot", default: false, null: false
    t.bigint "ranking_consolidation_id", null: false
    t.jsonb "ranking_snapshot", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["assessment_session_id"], name: "index_ranking_consolidation_sessions_on_assessment_session_id"
    t.index ["ranking_consolidation_id", "assessment_session_id"], name: "index_consolidation_sessions_on_consolidation_and_session", unique: true
    t.index ["ranking_consolidation_id"], name: "idx_on_ranking_consolidation_id_c8618d652c"
  end

  create_table "ranking_consolidations", force: :cascade do |t|
    t.bigint "assessment_definition_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "name"
    t.text "notes"
    t.datetime "published_at"
    t.datetime "recalculated_at"
    t.bigint "recalculated_by_id"
    t.jsonb "source_warnings", default: [], null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["assessment_definition_id"], name: "index_ranking_consolidations_on_assessment_definition_id"
    t.index ["created_by_id"], name: "index_ranking_consolidations_on_created_by_id"
    t.index ["recalculated_by_id"], name: "index_ranking_consolidations_on_recalculated_by_id"
    t.index ["status"], name: "index_ranking_consolidations_on_status"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text, 'withdrawn'::character varying::text])", name: "ranking_consolidations_status"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.string "api_token"
    t.datetime "api_token_expires_at"
    t.datetime "created_at", null: false
    t.bigint "impersonated_user_id"
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["api_token"], name: "index_sessions_on_api_token", unique: true
    t.index ["impersonated_user_id"], name: "index_sessions_on_impersonated_user_id"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "skills", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description"
    t.string "slug"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_skills_on_category_id"
    t.index ["created_by_id"], name: "index_skills_on_created_by_id"
    t.index ["slug"], name: "index_skills_on_slug", unique: true
  end

  create_table "training_focuses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "custom_focus"
    t.text "description"
    t.integer "position", default: 0, null: false
    t.bigint "skill_id"
    t.bigint "training_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["skill_id"], name: "index_training_focuses_on_skill_id"
    t.index ["training_session_id", "position"], name: "index_training_focuses_on_training_session_id_and_position"
    t.index ["training_session_id", "skill_id"], name: "index_training_focuses_on_session_and_skill", unique: true
    t.index ["training_session_id"], name: "index_training_focuses_on_training_session_id"
    t.check_constraint "\"position\" >= 0", name: "training_focuses_position_non_negative"
    t.check_constraint "skill_id IS NOT NULL AND custom_focus IS NULL OR skill_id IS NULL AND custom_focus IS NOT NULL", name: "training_focuses_skill_xor_custom_focus"
  end

  create_table "training_session_drills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "drill_id", null: false
    t.integer "duration_minutes"
    t.text "notes"
    t.integer "position", default: 0, null: false
    t.bigint "training_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["drill_id"], name: "index_training_session_drills_on_drill_id"
    t.index ["training_session_id", "drill_id"], name: "index_training_session_drills_on_session_and_drill", unique: true
    t.index ["training_session_id", "position"], name: "index_training_session_drills_on_session_and_position"
    t.index ["training_session_id"], name: "index_training_session_drills_on_training_session_id"
    t.check_constraint "\"position\" >= 0", name: "training_session_drills_position_non_negative"
    t.check_constraint "duration_minutes IS NULL OR duration_minutes > 0", name: "training_session_drills_duration_minutes_positive"
  end

  create_table "training_session_participants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.bigint "player_profile_id", null: false
    t.string "status", default: "invited", null: false
    t.bigint "training_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["player_profile_id"], name: "index_training_session_participants_on_player_profile_id"
    t.index ["status"], name: "index_training_session_participants_on_status"
    t.index ["training_session_id", "player_profile_id"], name: "index_training_session_participants_on_session_and_player", unique: true
    t.index ["training_session_id"], name: "index_training_session_participants_on_training_session_id"
  end

  create_table "training_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description"
    t.datetime "ends_at", null: false
    t.string "location"
    t.datetime "starts_at", null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "shared", null: false
    t.index ["created_by_id"], name: "index_training_sessions_on_created_by_id"
    t.index ["starts_at"], name: "index_training_sessions_on_starts_at"
    t.index ["status"], name: "index_training_sessions_on_status"
    t.index ["visibility"], name: "index_training_sessions_on_visibility"
    t.check_constraint "ends_at > starts_at", name: "training_sessions_ends_at_after_starts_at"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'scheduled'::character varying::text, 'cancelled'::character varying::text, 'completed'::character varying::text])", name: "training_sessions_status"
  end

  create_table "user_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "role_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "email_verification_sent_at"
    t.string "email_verification_token_digest"
    t.datetime "email_verified_at"
    t.string "name"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["email_verification_token_digest"], name: "index_users_on_email_verification_token_digest"
  end

  create_table "video_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_video_categories_on_created_by_id"
    t.index ["name"], name: "index_video_categories_on_name", unique: true
    t.index ["position"], name: "index_video_categories_on_position"
    t.index ["slug"], name: "index_video_categories_on_slug", unique: true
  end

  create_table "video_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "end_seconds"
    t.integer "position"
    t.bigint "referenced_id", null: false
    t.string "referenced_type", null: false
    t.integer "start_seconds"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.index ["referenced_type", "referenced_id", "position"], name: "index_video_references_on_referenced_and_position"
    t.index ["referenced_type", "referenced_id"], name: "index_video_references_on_referenced"
    t.index ["video_id"], name: "index_video_references_on_video_id"
    t.check_constraint "end_seconds IS NULL OR end_seconds >= 0", name: "video_references_end_seconds_non_negative"
    t.check_constraint "end_seconds IS NULL OR start_seconds IS NULL OR end_seconds > start_seconds", name: "video_references_end_after_start"
    t.check_constraint "start_seconds IS NULL OR start_seconds >= 0", name: "video_references_start_seconds_non_negative"
  end

  create_table "video_taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.bigint "video_tag_id", null: false
    t.index ["video_id", "video_tag_id"], name: "index_video_taggings_on_video_id_and_video_tag_id", unique: true
    t.index ["video_id"], name: "index_video_taggings_on_video_id"
    t.index ["video_tag_id"], name: "index_video_taggings_on_video_tag_id"
  end

  create_table "video_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_video_tags_on_lower_name", unique: true
    t.index ["name"], name: "index_video_tags_on_name", unique: true
    t.index ["position"], name: "index_video_tags_on_position"
  end

  create_table "videos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description"
    t.integer "duration_seconds"
    t.string "provider", null: false
    t.string "provider_video_id"
    t.string "source_url"
    t.string "storage_key"
    t.string "thumbnail_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "video_category_id"
    t.index ["created_by_id"], name: "index_videos_on_created_by_id"
    t.index ["provider", "provider_video_id"], name: "index_videos_on_provider_and_provider_video_id", unique: true, where: "(provider_video_id IS NOT NULL)"
    t.index ["provider"], name: "index_videos_on_provider"
    t.index ["provider_video_id"], name: "index_videos_on_provider_video_id"
  end

  add_foreign_key "account_addresses", "accounts"
  add_foreign_key "accounts", "people"
  add_foreign_key "accounts", "users"
  add_foreign_key "admin_activities", "users"
  add_foreign_key "assessment_categories", "assessment_definitions"
  add_foreign_key "assessment_categories", "categories"
  add_foreign_key "assessment_categories", "category_customs"
  add_foreign_key "assessment_category_scores", "assessment_categories"
  add_foreign_key "assessment_category_scores", "assessments"
  add_foreign_key "assessment_category_scores", "criteria"
  add_foreign_key "assessment_definitions", "users", column: "created_by_id"
  add_foreign_key "assessment_session_participants", "assessment_sessions"
  add_foreign_key "assessment_session_participants", "player_profiles"
  add_foreign_key "assessment_sessions", "assessment_definitions"
  add_foreign_key "assessment_sessions", "coach_profiles"
  add_foreign_key "assessment_sessions", "groups"
  add_foreign_key "assessment_sessions", "users", column: "created_by_id"
  add_foreign_key "assessments", "assessment_definitions"
  add_foreign_key "assessments", "assessment_sessions", on_delete: :nullify
  add_foreign_key "assessments", "categories"
  add_foreign_key "assessments", "coach_profiles"
  add_foreign_key "assessments", "player_profiles"
  add_foreign_key "assessments", "training_sessions", on_delete: :nullify
  add_foreign_key "assessments", "users", column: "created_by_id"
  add_foreign_key "category_customs", "users", column: "created_by_id"
  add_foreign_key "coach_profiles", "people"
  add_foreign_key "coach_profiles", "users", column: "created_by_id"
  add_foreign_key "criteria", "assessment_categories"
  add_foreign_key "drill_skills", "drills"
  add_foreign_key "drill_skills", "skills"
  add_foreign_key "drills", "users", column: "created_by_id"
  add_foreign_key "group_memberships", "groups"
  add_foreign_key "group_memberships", "player_profiles"
  add_foreign_key "groups", "users", column: "created_by_id"
  add_foreign_key "log_objects", "logs"
  add_foreign_key "people", "people", column: "merged_into_id"
  add_foreign_key "people", "users", column: "created_by_id"
  add_foreign_key "person_aliases", "people"
  add_foreign_key "player_profiles", "people"
  add_foreign_key "player_profiles", "users", column: "created_by_id"
  add_foreign_key "ranking_consolidation_rows", "player_profiles"
  add_foreign_key "ranking_consolidation_rows", "ranking_consolidations"
  add_foreign_key "ranking_consolidation_sessions", "assessment_sessions"
  add_foreign_key "ranking_consolidation_sessions", "ranking_consolidations"
  add_foreign_key "ranking_consolidations", "assessment_definitions"
  add_foreign_key "ranking_consolidations", "users", column: "created_by_id"
  add_foreign_key "ranking_consolidations", "users", column: "recalculated_by_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "sessions", "users", column: "impersonated_user_id"
  add_foreign_key "skills", "categories"
  add_foreign_key "skills", "users", column: "created_by_id"
  add_foreign_key "training_focuses", "skills"
  add_foreign_key "training_focuses", "training_sessions"
  add_foreign_key "training_session_drills", "drills"
  add_foreign_key "training_session_drills", "training_sessions"
  add_foreign_key "training_session_participants", "player_profiles"
  add_foreign_key "training_session_participants", "training_sessions"
  add_foreign_key "training_sessions", "users", column: "created_by_id"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "video_categories", "users", column: "created_by_id"
  add_foreign_key "video_references", "videos"
  add_foreign_key "video_taggings", "video_tags"
  add_foreign_key "video_taggings", "videos"
  add_foreign_key "videos", "users", column: "created_by_id"
  add_foreign_key "videos", "video_categories", on_delete: :nullify
end
