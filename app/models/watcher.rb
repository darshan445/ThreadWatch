class Watcher < ApplicationRecord
  belongs_to :user
  has_many   :leads,     foreign_key: :watcher_id, dependent: :destroy
  has_many   :raw_posts, through: :leads

  REDDIT_TIME_WINDOWS = %w[hour day week month year all].freeze

  after_commit :enqueue_initial_check, on: :create

  validates :name,       presence: true
  validates :keywords,   presence: true
  validates :subreddits, presence: true
  validates :fetch_limit, numericality: {
    only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 100
  }
  validates :reddit_time_filter, inclusion: { in: REDDIT_TIME_WINDOWS }

  scope :active,   -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def keywords_list
    keywords.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def subreddits_list
    subreddits.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  private

  # First Reddit check right away; cron still runs ScheduleWatchersJob every 30m for all watchers.
  def enqueue_initial_check
    return unless active?

    WatcherCheckJob.perform_later(id)
  end
end
