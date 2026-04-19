class WatcherCheckJob < ApplicationJob
  queue_as :default

  def perform(watcher_id)
    watcher = Watcher.find(watcher_id)
    return unless watcher.active?
    return unless watcher.user.active_access?
    Scrapers::RedditScraper.call(watcher: watcher)
  end
end
