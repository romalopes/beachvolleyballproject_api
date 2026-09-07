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

ActiveRecord::Schema[8.1].define(version: 2026_09_06_063737) do
  create_schema "extensions"

  # These are extensions that must be enabled in order to support this database
  enable_extension "extensions.pg_stat_statements"
  enable_extension "extensions.pgcrypto"
  enable_extension "extensions.uuid-ossp"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vault.supabase_vault"

  create_table "public.categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "public.drill_skills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "drill_id", null: false
    t.bigint "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["drill_id", "skill_id"], name: "index_drill_skills_on_drill_id_and_skill_id", unique: true
    t.index ["skill_id"], name: "index_drill_skills_on_skill_id"
  end

  create_table "public.drills", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "difficulty_level"
    t.integer "player_count"
    t.text "setup_instructions"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "public.media_assets", force: :cascade do |t|
    t.string "asset_type"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "drill_id", null: false
    t.bigint "skill_id"
    t.string "thumbnail_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "video_url"
    t.index ["drill_id"], name: "index_media_assets_on_drill_id"
    t.index ["skill_id"], name: "index_media_assets_on_skill_id"
  end

  create_table "public.skills", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_skills_on_category_id"
  end

  create_table "public.training_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "drill_id", null: false
    t.string "location"
    t.text "notes"
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["drill_id"], name: "index_training_sessions_on_drill_id"
  end

  add_foreign_key "public.drill_skills", "public.drills"
  add_foreign_key "public.drill_skills", "public.skills"
  add_foreign_key "public.media_assets", "public.drills"
  add_foreign_key "public.media_assets", "public.skills"
  add_foreign_key "public.skills", "public.categories"
  add_foreign_key "public.training_sessions", "public.drills"

end
