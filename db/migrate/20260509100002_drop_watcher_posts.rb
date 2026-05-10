class DropWatcherPosts < ActiveRecord::Migration[7.1]
  def up
    drop_table :watcher_posts
  end

  def down
    create_table :watcher_posts do |t|
      t.bigint  :watcher_id,  null: false
      t.bigint  :raw_post_id, null: false
      t.boolean :processed,   null: false, default: false
      t.timestamps
    end
    add_index :watcher_posts, %i[watcher_id raw_post_id], unique: true
    add_index :watcher_posts, :raw_post_id
    add_foreign_key :watcher_posts, :watchers
    add_foreign_key :watcher_posts, :raw_posts
  end
end
