class CreatePipelineRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :pipeline_runs do |t|
      t.string   :status,           null: false, default: "pending"
      t.text     :subreddits                      # JSON array
      t.integer  :limit_per_phrase, default: 100
      t.integer  :top_clusters,     default: 10
      t.boolean  :force_reprocess,  default: false
      t.text     :log_output
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :pipeline_runs, :status
    add_index :pipeline_runs, :created_at
  end
end
