class CreateLeads < ActiveRecord::Migration[7.1]
  def change
    create_table :leads do |t|
      t.references :monitor,  null: false, foreign_key: true
      t.references :raw_post, null: false, foreign_key: true
      t.integer    :score,    null: false, default: 0
      t.string     :status,   null: false, default: "new"
      t.datetime   :replied_at
      t.text       :notes

      t.timestamps
    end

    # t.references already creates individual indexes on monitor_id and raw_post_id;
    # add the composite unique index and status index on top.
    add_index :leads, [:monitor_id, :raw_post_id], unique: true, name: "index_leads_on_monitor_and_post"
    add_index :leads, :status
  end
end
