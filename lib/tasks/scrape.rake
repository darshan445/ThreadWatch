namespace :scrape do
  desc <<~DESC
    Scrape Reddit using a Watcher's keywords and subreddits.

    Usage:
      rails scrape:reddit WATCHER_ID=1
      rails scrape:reddit SUBREDDITS=entrepreneur,freelance KEYWORDS="I wish there was,I'd pay for" LIMIT=100

    ENV vars:
      WATCHER_ID   ID of an existing Watcher record (takes priority)
      SUBREDDITS   Comma-separated subreddit names (default: entrepreneur)
      KEYWORDS     Comma-separated search phrases (default: "I wish there was")
      LIMIT        Optional. Overrides watcher fetch_limit; 1–100 (omit to use watcher or 100 for ad-hoc)
      TIME_FILTER  Optional. hour|day|week|month|year|all — overrides watcher (default day)
  DESC
  task reddit: :environment do
    monitor = if ENV["WATCHER_ID"]
      Watcher.find(ENV["WATCHER_ID"])
    else
      Watcher.new(
        subreddits: ENV.fetch("SUBREDDITS", "entrepreneur"),
        keywords:   ENV.fetch("KEYWORDS",   "I wish there was,I'd pay for,does anyone know a tool,why is there no app for")
      )
    end

    limit       = ENV["LIMIT"].present? ? ENV["LIMIT"].to_i : nil
    time_filter = ENV["TIME_FILTER"].presence

    puts "Subreddits : #{monitor.subreddits_list.join(", ")}"
    puts "Keywords   : #{monitor.keywords_list.join(", ")}"
    puts "Limit/run  : #{limit || monitor.try(:fetch_limit) || "default"}"
    puts "Time window: #{time_filter || monitor.try(:reddit_time_filter) || "day"}"
    puts "Total requests: up to #{monitor.subreddits_list.count * monitor.keywords_list.count}"
    puts "-" * 50

    started_at = Time.current
    result     = Scrapers::RedditScraper.call(watcher: monitor, limit: limit, time_filter: time_filter)
    elapsed    = (Time.current - started_at).round(1)

    puts "-" * 50
    puts "Saved         : #{result.saved}"
    puts "Skipped       : #{result.skipped} (already in DB)"
    puts "Leads created : #{result.leads_created}"
    puts "Errors        : #{result.errors.count}"
    puts "Time          : #{elapsed}s"

    if result.errors.any?
      puts "\nErrors:"
      result.errors.each do |e|
        puts "  [#{e[:subreddit]}] #{e[:phrase].inspect} — #{e[:message]}"
      end
      exit 1
    end
  end
end
