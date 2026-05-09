class DropPipelineRunsAndProcessedColumn < ActiveRecord::Migration[7.1]
  def up
    drop_table :pipeline_runs
    remove_column :raw_posts, :processed
  end

  def down
    add_column :raw_posts, :processed, :boolean, default: false, null: false
    add_index  :raw_posts, :processed

    create_table :pipeline_runs do |t|
      t.string   "status",          default: "pending", null: false
      t.text     "subreddits"
      t.integer  "limit_per_phrase", default: 100
      t.integer  "top_clusters",     default: 10
      t.boolean  "force_reprocess",  default: false
      t.text     "log_output"
      t.datetime "started_at"
      t.datetime "finished_at"
      t.string   "time_filter",      default: "year", null: false
      t.timestamps null: false
    end
    add_index :pipeline_runs, :status
    add_index :pipeline_runs, :created_at
  end
end
