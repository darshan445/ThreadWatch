class CreateRawPosts < ActiveRecord::Migration[7.1]
  def change
    create_table :raw_posts do |t|
      t.string :source, null: false       # "reddit" or "g2"
      t.string :external_id, null: false  # reddit post id, g2 review id
      t.string :url
      t.string :title
      t.text   :body
      t.jsonb  :metadata, default: {}       # raw API response extras
      t.datetime :scraped_at

      t.timestamps
    end

    add_index :raw_posts, [:source, :external_id], unique: true
  end
end
