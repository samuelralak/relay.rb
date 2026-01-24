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

ActiveRecord::Schema[8.1].define(version: 2026_01_23_194232) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "uuid-ossp"

  create_table "event_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.uuid "event_id", null: false
    t.integer "kind", null: false
    t.datetime "nostr_created_at", null: false
    t.integer "tag_index", null: false
    t.string "tag_name", limit: 1, null: false
    t.string "tag_value", limit: 255, null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "idx_event_tags_deleted_at"
    t.index ["event_id"], name: "index_event_tags_on_event_id"
    t.index ["tag_name", "kind", "tag_value", "nostr_created_at", "event_id"], name: "idx_event_tags_kind_covering", order: { nostr_created_at: :desc }
    t.index ["tag_name", "tag_value", "nostr_created_at", "event_id"], name: "idx_event_tags_covering", order: { nostr_created_at: :desc }
    t.index ["tag_name", "tag_value"], name: "idx_event_tags_lookup"
  end

  create_table "events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "content", default: "", null: false
    t.datetime "created_at", null: false
    t.string "d_tag", limit: 255
    t.datetime "deleted_at"
    t.string "event_id", limit: 64, null: false
    t.datetime "expires_at"
    t.datetime "first_seen_at", null: false
    t.integer "kind", null: false
    t.datetime "nostr_created_at", null: false
    t.string "pubkey", limit: 64, null: false
    t.jsonb "raw_event", null: false
    t.string "sig", limit: 128, null: false
    t.jsonb "tags", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "idx_events_deleted_at"
    t.index ["event_id"], name: "idx_events_event_id", unique: true
    t.index ["expires_at"], name: "idx_events_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["kind", "nostr_created_at"], name: "idx_events_kind_created_at", order: { nostr_created_at: :desc }
    t.index ["pubkey", "kind", "d_tag"], name: "idx_events_addressable", where: "(d_tag IS NOT NULL)"
    t.index ["pubkey", "kind"], name: "idx_events_pubkey_kind"
    t.index ["pubkey", "nostr_created_at"], name: "idx_events_pubkey_created_at", order: { nostr_created_at: :desc }
    t.index ["tags"], name: "idx_events_tags_gin", using: :gin
    t.check_constraint "event_id::text ~ '^[a-f0-9]{64}$'::text", name: "check_event_id_hex"
    t.check_constraint "kind >= 0 AND kind <= 65535", name: "check_kind_range"
    t.check_constraint "pubkey::text ~ '^[a-f0-9]{64}$'::text", name: "check_pubkey_hex"
    t.check_constraint "sig::text ~ '^[a-f0-9]{128}$'::text", name: "check_sig_hex"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "sync_states", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "backfill_target"
    t.datetime "backfill_until"
    t.datetime "created_at", null: false
    t.string "direction", limit: 10, default: "down", null: false
    t.text "error_message"
    t.integer "events_downloaded", default: 0, null: false
    t.integer "events_uploaded", default: 0, null: false
    t.string "filter_hash", limit: 64
    t.string "last_download_event_id", limit: 64
    t.datetime "last_download_timestamp"
    t.datetime "last_synced_at"
    t.string "last_upload_event_id", limit: 64
    t.datetime "last_upload_timestamp"
    t.string "relay_url", limit: 255, null: false
    t.string "status", limit: 20, default: "idle", null: false
    t.datetime "updated_at", null: false
    t.index ["relay_url", "filter_hash"], name: "idx_sync_states_relay_filter", unique: true
    t.index ["status"], name: "idx_sync_states_status"
  end

  add_foreign_key "event_tags", "events", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
