class CreateReplyTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :reply_templates do |t|
      t.references :user,      null: false, foreign_key: true
      t.string     :name,      null: false
      t.text       :body,      null: false
      t.integer    :use_count, null: false, default: 0

      t.timestamps
    end
  end
end
