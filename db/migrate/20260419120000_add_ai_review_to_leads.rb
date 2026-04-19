class AddAiReviewToLeads < ActiveRecord::Migration[7.1]
  def up
    add_column :leads, :ai_match, :boolean
    add_column :leads, :ai_reason, :text
    add_column :leads, :ai_reviewed_at, :datetime

    # Pre-feature leads behave as already reviewed & matched
    execute <<-SQL.squish
      UPDATE leads
      SET ai_match = TRUE, ai_reviewed_at = NOW()
      WHERE ai_match IS NULL
    SQL
  end

  def down
    remove_column :leads, :ai_reviewed_at
    remove_column :leads, :ai_reason
    remove_column :leads, :ai_match
  end
end
