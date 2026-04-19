class ScrapeJob < ApplicationJob
  queue_as :default

  ScrapeJobError = Class.new(StandardError)

  def perform(run_id)
    run = PipelineRun.find(run_id)
    run.update!(status: "running", started_at: Time.current)
    run.broadcast_status_update
    run.append_log("Scrape started")
    run.append_log("Subreddits: #{run.subreddits_list.join(", ")}")
    run.append_log("Limit: #{run.limit_per_phrase}  Time filter: #{run.time_filter}")
    run.append_log("─" * 50)

    step_scrape(run)

    run.append_log("─" * 50)
    run.append_log("Done — Posts: #{RawPost.count} | Comments: #{PostComment.count}")
    run.update!(status: "complete", finished_at: Time.current)
    run.broadcast_status_update

  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "[ScrapeJob] PipelineRun #{run_id} not found — job aborted"
  rescue ScrapeJobError => e
    run&.append_log("STOPPED: #{e.message}")
    run&.update!(status: "failed", finished_at: Time.current)
    run&.broadcast_status_update
  rescue => e
    run&.append_log("UNEXPECTED ERROR: #{e.class} — #{e.message}")
    run&.update!(status: "failed", finished_at: Time.current)
    run&.broadcast_status_update
    raise
  end

  private

  def step_scrape(run)
    phrases = Scrapers::RedditScraper::PAIN_PHRASES
    run.append_log("Phrases: #{phrases.count} | Requests: up to #{run.subreddits_list.count * phrases.count}")

    result = Scrapers::RedditScraper.call(
      subreddits:  run.subreddits_list,
      limit:       run.limit_per_phrase,
      time_filter: run.time_filter
    )

    run.append_log("Saved: #{result.saved}  Skipped: #{result.skipped}  Errors: #{result.errors.count}")
    run.append_log("DB total: #{RawPost.count} posts  #{PostComment.count} comments")

    if result.errors.any?
      result.errors.first(5).each { |e| run.append_log("! #{e[:subreddit]} / #{e[:phrase].inspect}: #{e[:message]}") }
    end

    raise ScrapeJobError, "Scrape produced no posts" if result.saved.zero? && result.skipped.zero?
  end
end
