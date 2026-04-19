class CreatePostComments < ActiveRecord::Migration[7.1]
  def change
    create_table :post_comments do |t|
      t.integer :raw_post_id, null: false
      t.string  :comment_id,  null: false
      t.text    :body,        null: false
      t.integer :score,       null: false, default: 0
      t.integer :depth,       null: false, default: 0
      t.timestamps
    end

    add_index :post_comments, :raw_post_id
    add_index :post_comments, :comment_id, unique: true
    add_foreign_key :post_comments, :raw_posts
  end
end
