redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_server do |config|
  config.on(:startup) do
    Sidekiq::Cron::Job.create(
      name:  "Schedule all watchers every 1 hour",
      cron:  "0 * * * *",
      class: "ScheduleWatchersJob"
    )

    Sidekiq::Cron::Job.create(
      name:  "Send daily digest at 8am",
      cron:  "0 8 * * *",
      class: "DailyDigestJob"
    )
  end
end
