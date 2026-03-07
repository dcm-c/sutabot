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

ActiveRecord::Schema[8.0].define(version: 2026_03_07_072714) do
  create_table "channel_settings", force: :cascade do |t|
    t.string "module_name"
    t.string "display_name"
    t.string "channel_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "daily_verses", force: :cascade do |t|
    t.string "reference"
    t.text "content"
    t.string "image_url"
    t.integer "likes"
    t.integer "dislikes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "horoscopes", force: :cascade do |t|
    t.string "sign"
    t.text "content"
    t.date "target_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "module_configs", force: :cascade do |t|
    t.string "guild_id"
    t.string "module_name"
    t.text "channel_ids"
    t.text "allowed_role_ids"
    t.boolean "ratings_enabled"
    t.string "schedule_time"
    t.string "subreddit_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "output_channel_id"
    t.boolean "exclude_channels"
    t.text "custom_data"
  end

  create_table "ratings", force: :cascade do |t|
    t.string "user_discord_id"
    t.integer "score"
    t.string "rateable_type", null: false
    t.integer "rateable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rateable_type", "rateable_id"], name: "index_ratings_on_rateable"
  end

  create_table "reddit_posts", force: :cascade do |t|
    t.string "title"
    t.string "url"
    t.string "image_url"
    t.integer "likes"
    t.integer "dislikes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "subreddit"
    t.string "author"
    t.text "content"
    t.string "reddit_id"
  end

  create_table "reddit_states", force: :cascade do |t|
    t.string "last_post_timestamp"
    t.integer "current_interval"
    t.integer "success_streak"
    t.string "status_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "server_settings", force: :cascade do |t|
    t.string "guild_id"
    t.string "module_name"
    t.string "channel_id"
    t.boolean "ratings_enabled"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "subreddit_name"
    t.string "horoscope_channel_id"
    t.boolean "horoscope_ratings_enabled"
    t.string "schedule_time"
  end

  create_table "users", force: :cascade do |t|
    t.string "uid"
    t.string "name"
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
