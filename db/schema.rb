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

ActiveRecord::Schema[8.1].define(version: 2026_09_19_000008) do
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
    t.date "date_of_birth"
    t.string "first_name"
    t.string "last_name"
    t.string "phone"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
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

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_categories_on_slug", unique: true
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
    t.string "difficulty_level", default: "intermediate", null: false
    t.integer "ideal_num_players", default: 4, null: false
    t.integer "max_players", default: 8, null: false
    t.integer "min_players", default: 2, null: false
    t.text "setup_instructions"
    t.string "slug"
    t.string "title"
    t.string "training_stage", default: "beginning", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_drills_on_created_by_id"
    t.index ["slug"], name: "index_drills_on_slug", unique: true
    t.index ["training_stage"], name: "index_drills_on_training_stage"
    t.check_constraint "difficulty_level::text = ANY (ARRAY['beginner'::character varying, 'intermediate'::character varying, 'advanced'::character varying]::text[])", name: "drills_difficulty_level_check"
    t.check_constraint "ideal_num_players >= min_players AND ideal_num_players <= max_players", name: "drills_ideal_players_check"
    t.check_constraint "min_players <= max_players", name: "drills_player_range_check"
    t.check_constraint "training_stage::text = ANY (ARRAY['warmup'::character varying, 'beginning'::character varying, 'middle'::character varying, 'end'::character varying]::text[])", name: "drills_training_stage_check"
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
    t.index ["created_by_id"], name: "index_training_sessions_on_created_by_id"
    t.index ["starts_at"], name: "index_training_sessions_on_starts_at"
    t.index ["status"], name: "index_training_sessions_on_status"
    t.check_constraint "ends_at > starts_at", name: "training_sessions_ends_at_after_starts_at"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'scheduled'::character varying, 'cancelled'::character varying, 'completed'::character varying]::text[])", name: "training_sessions_status"
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
    t.string "name"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
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
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_video_tags_on_lower_name", unique: true
    t.index ["name"], name: "index_video_tags_on_name", unique: true
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
  add_foreign_key "accounts", "users"
  add_foreign_key "admin_activities", "users"
  add_foreign_key "drill_skills", "drills"
  add_foreign_key "drill_skills", "skills"
  add_foreign_key "drills", "users", column: "created_by_id"
  add_foreign_key "log_objects", "logs"
  add_foreign_key "sessions", "users"
  add_foreign_key "sessions", "users", column: "impersonated_user_id"
  add_foreign_key "skills", "categories"
  add_foreign_key "skills", "users", column: "created_by_id"
  add_foreign_key "training_focuses", "skills"
  add_foreign_key "training_focuses", "training_sessions"
  add_foreign_key "training_session_drills", "drills"
  add_foreign_key "training_session_drills", "training_sessions"
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
