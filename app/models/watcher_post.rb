# frozen_string_literal: true

# Tracks which RawPosts each Watcher has already processed (keyword-passed + AI-evaluated).
# processed=true means the full pipeline has run for this watcher+post pair, so
# subsequent scrape runs skip it and avoid redundant Gemini API calls.
class WatcherPost < ApplicationRecord
  belongs_to :watcher
  belongs_to :raw_post

  scope :processed,   -> { where(processed: true) }
  scope :unprocessed, -> { where(processed: false) }
end
