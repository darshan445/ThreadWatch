class Lead < ApplicationRecord
  STATUSES = %w[new saved replied converted ignored].freeze

  belongs_to :watcher, foreign_key: :watcher_id
  belongs_to :raw_post

  validates :status, inclusion: { in: STATUSES }

  scope :by_status,  ->(s) { where(status: s) }
  scope :fresh,      -> { where(status: "new") }
  scope :actionable, -> { where(status: %w[new saved]) }
  scope :by_score,   -> { order(score: :desc) }
  # Excludes AI-rejected leads (ai_match == false). Pending review (NULL) and matched (true) stay visible.
  scope :not_ai_rejected, -> { where.not(ai_match: false) }
  scope :ai_digestable, -> { where(ai_match: true) }

  def mark_replied!
    update!(status: "replied", replied_at: Time.current)
  end
end
