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

ActiveRecord::Schema[7.1].define(version: 2026_05_09_100002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "leads", force: :cascade do |t|
    t.bigint "watcher_id", null: false
    t.bigint "raw_post_id", null: false
    t.integer "score", default: 0, null: false
    t.string "status", default: "new", null: false
    t.datetime "replied_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "ai_match"
    t.text "ai_reason"
    t.datetime "ai_reviewed_at"
    t.integer "ai_confidence"
    t.index ["raw_post_id"], name: "index_leads_on_raw_post_id"
    t.index ["status"], name: "index_leads_on_status"
    t.index ["watcher_id", "raw_post_id"], name: "index_leads_on_watcher_and_post", unique: true
    t.index ["watcher_id"], name: "index_leads_on_watcher_id"
  end

  create_table "post_comments", force: :cascade do |t|
    t.integer "raw_post_id", null: false
    t.string "comment_id", null: false
    t.text "body", null: false
    t.integer "score", default: 0, null: false
    t.integer "depth", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["comment_id"], name: "index_post_comments_on_comment_id", unique: true
    t.index ["raw_post_id"], name: "index_post_comments_on_raw_post_id"
  end

  create_table "raw_posts", force: :cascade do |t|
    t.string "source", null: false
    t.string "external_id", null: false
    t.string "url"
    t.string "title"
    t.text "body"
    t.jsonb "metadata", default: {}
    t.datetime "scraped_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "upvotes"
    t.integer "comment_count"
    t.index ["source", "external_id"], name: "index_raw_posts_on_source_and_external_id", unique: true
  end

  create_table "reply_templates", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.text "body", null: false
    t.integer "use_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_reply_templates_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "name"
    t.datetime "trial_ends_at"
    t.boolean "subscribed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "watchers", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.text "keywords", null: false
    t.text "subreddits", null: false
    t.boolean "active", default: true, null: false
    t.datetime "last_checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "fetch_limit", default: 25, null: false
    t.string "reddit_time_filter", default: "day", null: false
    t.string "description"
    t.index ["active"], name: "index_watchers_on_active"
    t.index ["user_id"], name: "index_watchers_on_user_id"
  end

  add_foreign_key "leads", "raw_posts"
  add_foreign_key "leads", "watchers"
  add_foreign_key "post_comments", "raw_posts"
  add_foreign_key "reply_templates", "users"
  add_foreign_key "watchers", "users"
end
