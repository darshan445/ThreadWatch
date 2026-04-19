class RenameMonitorsToWatchers < ActiveRecord::Migration[7.1]
  def change
    # Drop FKs before renaming
    remove_foreign_key :leads, :monitors
    remove_foreign_key :monitors, :users

    # Drop leads indexes that reference monitor_id before renaming column
    remove_index :leads, name: "index_leads_on_monitor_id"
    remove_index :leads, name: "index_leads_on_monitor_and_post"

    rename_table  :monitors, :watchers
    rename_column :leads, :monitor_id, :watcher_id

    # Re-add leads indexes with updated names
    add_index :leads, :watcher_id,                    name: "index_leads_on_watcher_id"
    add_index :leads, [:watcher_id, :raw_post_id],    name: "index_leads_on_watcher_and_post", unique: true

    # Re-add FKs
    add_foreign_key :leads,    :watchers
    add_foreign_key :watchers, :users
  end
end
