class AddDescriptionToWatchers < ActiveRecord::Migration[7.1]
  def change
    add_column :watchers, :description, :string
  end
end
