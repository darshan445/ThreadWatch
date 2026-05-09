# frozen_string_literal: true

# Populates watcher.keywords and watcher.subreddits from description using:
#   Layer 1 — Gemini (generates keyword phrases + subreddit search terms)
#   Layer 2 — Reddit subreddits/search.json (validates / discovers real subreddit names)
# Always sets both attributes; falls back gracefully when AI or Reddit is unavailable.
class WatcherSetupService
  REDDIT_BASE     = "https://www.reddit.com"
  SUBREDDIT_LIMIT = 3   # Reddit results fetched per search query
  MAX_SUBREDDITS  = 10  # final cap on stored subreddits
  REQUEST_TIMEOUT = 8
  HEADERS         = { "User-Agent" => "thread-watch/1.0 by FrequentBike8327" }.freeze

  FALLBACK_SUBREDDITS = %w[
    entrepreneur smallbusiness freelance SaaS startups
    digitalnomad productivity Entrepreneur business
  ].freeze

  Result = Struct.new(:keywords, :subreddits, :errors, keyword_init: true)

  def self.call(watcher)
    new(watcher).call
  end

  def initialize(watcher)
    @watcher = watcher
    @errors  = []
  end

  def call
    unless GeminiClient.api_key?
      Rails.logger.warn "[WatcherSetupService] no Gemini key — using fallback"
      apply_fallback!
      return result
    end

    ai_result = call_ai
    subreddits = fetch_subreddits_from_reddit(ai_result[:subreddit_queries])

    @watcher.keywords   = ai_result[:keywords]
    @watcher.subreddits = subreddits.join(", ")

    Rails.logger.info(
      "[WatcherSetupService] done watcher=#{@watcher.name.inspect} " \
      "keywords=#{@watcher.keywords.truncate(200).inspect} " \
      "subreddits=#{@watcher.subreddits.inspect}"
    )

    result
  rescue => e
    Rails.logger.error "[WatcherSetupService] failed #{e.class}: #{e.message}"
    @errors << e.message
    apply_fallback!
    result
  end

  private

  def result
    Result.new(keywords: @watcher.keywords, subreddits: @watcher.subreddits, errors: @errors)
  end

  # ── AI ───────────────────────────────────────────────────────────────────

  def call_ai
    user_msg = Analyzers::WatcherSetupPrompt.build_user_message(@watcher)

    Rails.logger.info "[WatcherSetupService] calling Gemini"

    raw = GeminiClient.generate(
      system:     Analyzers::WatcherSetupPrompt::SYSTEM_PROMPT,
      user:       user_msg,
      max_tokens: 600
    )

    Rails.logger.info "[WatcherSetupService] Gemini raw=#{raw.truncate(600).inspect}"

    Analyzers::WatcherSetupPrompt.parse_response(raw)
  end

  # ── Reddit subreddit search ───────────────────────────────────────────────

  # Given AI-suggested search terms, hit Reddit's subreddits/search.json for each,
  # collect real display_name values, deduplicate, cap at MAX_SUBREDDITS.
  def fetch_subreddits_from_reddit(queries)
    return FALLBACK_SUBREDDITS.first(MAX_SUBREDDITS) if queries.blank?

    names = []

    queries.each do |query|
      found = search_subreddits(query.to_s.strip)
      names.concat(found)
      break if names.size >= MAX_SUBREDDITS
    end

    names = names.uniq.first(MAX_SUBREDDITS)

    if names.empty?
      Rails.logger.warn "[WatcherSetupService] no subreddits found via Reddit — using fallback"
      names = FALLBACK_SUBREDDITS.first(MAX_SUBREDDITS)
    end

    names
  end

  def search_subreddits(query)
    return [] if query.blank?

    url      = "#{REDDIT_BASE}/subreddits/search.json"
    response = HTTParty.get(url, query: { q: query, limit: SUBREDDIT_LIMIT },
                                 headers: HEADERS, timeout: REQUEST_TIMEOUT)

    unless response.success?
      Rails.logger.warn "[WatcherSetupService] Reddit subreddit search HTTP #{response.code} for #{query.inspect}"
      return []
    end

    children = response.dig("data", "children") || []
    names    = children
                 .select  { |c| c["kind"] == "t5" }
                 .map     { |c| c.dig("data", "display_name").to_s.strip }
                 .reject(&:blank?)

    Rails.logger.info "[WatcherSetupService] subreddit_search q=#{query.inspect} found=#{names.inspect}"
    names
  rescue => e
    Rails.logger.warn "[WatcherSetupService] subreddit_search error q=#{query.inspect} #{e.class}: #{e.message}"
    []
  end

  # ── Fallback ─────────────────────────────────────────────────────────────

  def apply_fallback!
    @watcher.keywords   = fallback_keywords unless @watcher.keywords.present?
    @watcher.subreddits = FALLBACK_SUBREDDITS.first(MAX_SUBREDDITS).join(", ") unless @watcher.subreddits.present?
  end

  def fallback_keywords
    desc  = @watcher.description.to_s.strip
    name  = @watcher.name.to_s.strip
    words = "#{name} #{desc}".downcase.scan(/[a-z]{3,}/).uniq.first(10)
    words.any? ? words.join(", ") : name
  end
end
