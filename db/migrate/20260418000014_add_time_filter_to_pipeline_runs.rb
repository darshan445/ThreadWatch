class AddTimeFilterToPipelineRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :pipeline_runs, :time_filter, :string, default: "year", null: false
  end
end
