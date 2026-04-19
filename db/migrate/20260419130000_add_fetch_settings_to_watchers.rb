class AddFetchSettingsToWatchers < ActiveRecord::Migration[7.1]
  def change
    add_column :watchers, :fetch_limit, :integer, default: 25, null: false
    add_column :watchers, :reddit_time_filter, :string, default: "day", null: false
  end
end
