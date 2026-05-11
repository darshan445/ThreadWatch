class AddPostedAtToRawPosts < ActiveRecord::Migration[7.1]
  def change
    add_column :raw_posts, :posted_at, :datetime
    add_index  :raw_posts, :posted_at
  end
end
