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

ActiveRecord::Schema[8.1].define(version: 2026_09_09_045039) do
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

  create_table "media_assets", force: :cascade do |t|
    t.string "asset_type"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "drill_id", null: false
    t.bigint "skill_id"
    t.string "slug"
    t.string "thumbnail_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.string "video_url"
    t.index ["drill_id"], name: "index_media_assets_on_drill_id"
    t.index ["skill_id"], name: "index_media_assets_on_skill_id"
    t.index ["slug"], name: "index_media_assets_on_slug", unique: true
    t.index ["uploaded_by_id"], name: "index_media_assets_on_uploaded_by_id"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
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

  create_table "training_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "drill_id", null: false
    t.string "location"
    t.text "notes"
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_training_sessions_on_created_by_id"
    t.index ["drill_id"], name: "index_training_sessions_on_drill_id"
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

  add_foreign_key "account_addresses", "accounts"
  add_foreign_key "accounts", "users"
  add_foreign_key "drill_skills", "drills"
  add_foreign_key "drill_skills", "skills"
  add_foreign_key "drills", "users", column: "created_by_id"
  add_foreign_key "media_assets", "drills"
  add_foreign_key "media_assets", "skills"
  add_foreign_key "media_assets", "users", column: "uploaded_by_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "skills", "categories"
  add_foreign_key "skills", "users", column: "created_by_id"
  add_foreign_key "training_sessions", "drills"
  add_foreign_key "training_sessions", "users", column: "created_by_id"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
end
