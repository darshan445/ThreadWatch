class AddProcessedToRawPosts < ActiveRecord::Migration[7.1]
  def change
    add_column :raw_posts, :processed, :boolean, null: false, default: false
    add_index  :raw_posts, :processed
  end
end
