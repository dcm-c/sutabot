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

ActiveRecord::Schema[8.1].define(version: 2026_03_07_151435) do
  create_table "channel_settings", force: :cascade do |t|
    t.string "channel_id"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "module_name"
    t.datetime "updated_at", null: false
  end

  create_table "daily_verses", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "dislikes"
    t.string "image_url"
    t.integer "likes"
    t.string "reference"
    t.datetime "updated_at", null: false
  end

  create_table "horoscopes", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "sign"
    t.date "target_date"
    t.datetime "updated_at", null: false
  end

  create_table "module_configs", force: :cascade do |t|
    t.text "allowed_role_ids"
    t.text "channel_ids"
    t.datetime "created_at", null: false
    t.text "custom_data"
    t.boolean "exclude_channels"
    t.string "guild_id"
    t.string "module_name"
    t.string "output_channel_id"
    t.boolean "ratings_enabled"
    t.string "schedule_time"
    t.string "subreddit_name"
    t.datetime "updated_at", null: false
  end

  create_table "ratings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "rateable_id", null: false
    t.string "rateable_type", null: false
    t.integer "score"
    t.datetime "updated_at", null: false
    t.string "user_discord_id"
    t.index ["rateable_type", "rateable_id"], name: "index_ratings_on_rateable"
  end

  create_table "reddit_posts", force: :cascade do |t|
    t.string "author"
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "dislikes"
    t.string "image_url"
    t.integer "likes"
    t.string "reddit_id"
    t.string "subreddit"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
  end

  create_table "reddit_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_interval"
    t.string "last_post_timestamp"
    t.string "status_message"
    t.integer "success_streak"
    t.datetime "updated_at", null: false
  end

  create_table "server_rules", force: :cascade do |t|
    t.json "actions"
    t.boolean "active", default: true
    t.json "conditions"
    t.datetime "created_at", null: false
    t.string "guild_id", null: false
    t.string "name", null: false
    t.string "rule_type", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id", "rule_type"], name: "index_server_rules_on_guild_id_and_rule_type"
  end

  create_table "server_settings", force: :cascade do |t|
    t.string "channel_id"
    t.datetime "created_at", null: false
    t.string "guild_id"
    t.string "horoscope_channel_id"
    t.boolean "horoscope_ratings_enabled"
    t.string "module_name"
    t.boolean "ratings_enabled"
    t.string "schedule_time"
    t.string "subreddit_name"
    t.datetime "updated_at", null: false
  end

  create_table "ticket_transcripts", force: :cascade do |t|
    t.string "closed_by"
    t.datetime "created_at", null: false
    t.string "guild_id"
    t.text "html_content"
    t.string "ticket_name"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "name"
    t.string "uid"
    t.datetime "updated_at", null: false
  end
end
