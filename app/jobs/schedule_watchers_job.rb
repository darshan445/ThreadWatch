class ScheduleWatchersJob < ApplicationJob
  queue_as :default

  def perform
    Watcher.where(active: true).find_each do |watcher|
      WatcherCheckJob.perform_later(watcher.id)
    end
  end
end
