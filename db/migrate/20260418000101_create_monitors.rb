class CreateMonitors < ActiveRecord::Migration[7.1]
  def change
    create_table :monitors do |t|
      t.references :user,       null: false, foreign_key: true
      t.string     :name,       null: false
      t.text       :keywords,   null: false
      t.text       :subreddits, null: false
      t.boolean    :active,     null: false, default: true
      t.datetime   :last_checked_at

      t.timestamps
    end

    add_index :monitors, :active
  end
end
