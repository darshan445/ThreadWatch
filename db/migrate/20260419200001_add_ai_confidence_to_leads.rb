class AddAiConfidenceToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :ai_confidence, :integer
  end
end
