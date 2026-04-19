class AddEngagementToRawPosts < ActiveRecord::Migration[7.1]
  def change
    add_column :raw_posts, :upvotes,       :integer
    add_column :raw_posts, :comment_count, :integer
  end
end
