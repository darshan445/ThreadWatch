require "cgi"

module Scrapers
  class RedditScraper
    BASE_URL      = "https://www.reddit.com"
    MAX_LIMIT     = 100

    # Delay between search requests (Reddit anonymous search is aggressively rate-limited).
    REQUEST_DELAY    = 2
    # Base 429 back-off; doubles each retry: 30 → 60 → 120s.
    RETRY_DELAY_BASE = 30
    MAX_RETRIES      = 3

    # Removed from Reddit +q before search so queries aren't dominated by filler.
    STOP_WORDS = %w[
      a an the is are was were be been being to of and or but if in on at for with from as it its we you he she they them
      this that these those i id ill ive im youre your my our their what which who how why when where there here
      dont cant wont isnt arent wasnt werent hasnt havent hadnt does did doing done
    ].freeze

    MAX_COMMENT_DEPTH = 3

    HEADERS = { "User-Agent" => "reddit-leads/1.0 by FrequentBike8327" }.freeze

    TIME_FILTERS = %w[hour day week month year all].freeze

    Result = Struct.new(:saved, :skipped, :leads_created, :errors, keyword_init: true) do
      def total    = saved + skipped
      def success? = errors.empty?
    end

    # +limit+ / +time_filter+ override watcher settings when present (e.g. rake ENV).
    def self.call(watcher:, limit: nil, time_filter: nil)
      resolved_limit = limit.presence || watcher.try(:fetch_limit) || MAX_LIMIT
      resolved_tf    = time_filter.presence || watcher.try(:reddit_time_filter) || "day"
      new(watcher: watcher, limit: resolved_limit.to_i, time_filter: resolved_tf.to_s).call
    end

    def initialize(watcher:, limit:, time_filter:)
      @watcher     = watcher
      @subreddits  = watcher.subreddits_list.map { |s| normalize_subreddit(s) }.reject(&:blank?)
      @phrases     = watcher.keywords_list
      @limit       = [[limit.to_i, 1].max, MAX_LIMIT].min
      @time_filter = TIME_FILTERS.include?(time_filter) ? time_filter : "day"

      @saved         = 0
      @skipped       = 0
      @skipped_keyword_layer  = 0
      @skipped_duplicate_post = 0
      @skipped_duplicate_lead = 0
      @skipped_rate_limited   = 0
      @leads_created = 0
      @errors        = []
      @total_fetched = 0
      @ai_lead_ids   = []

      @rate_limited_subreddits = Set.new
    end

    def call
      scraper_log(
        "start keywords=#{@watcher.keywords.to_s.truncate(240).inspect} " \
        "subreddits=#{@subreddits.inspect} phrases=#{@phrases.inspect} " \
        "limit=#{@limit} time_filter=#{@time_filter}"
      )

      @subreddits.each do |subreddit|
        scrape(subreddit)
      end

      flush_ai_reviews
      @watcher.update_column(:last_checked_at, Time.current)

      scraper_log(
        "done saved=#{@saved} skipped=#{@skipped} " \
        "(keyword_layer=#{@skipped_keyword_layer} duplicate_post=#{@skipped_duplicate_post} " \
        "duplicate_lead=#{@skipped_duplicate_lead} rate_limited=#{@skipped_rate_limited}) " \
        "leads_created=#{@leads_created} posts_processed=#{@total_fetched} " \
        "ai_enqueued=#{@ai_lead_ids.size} errors=#{@errors.size} " \
        "rate_limited_subreddits=#{@rate_limited_subreddits.to_a.inspect}"
      )

      Result.new(
        saved:         @saved,
        skipped:       @skipped,
        leads_created: @leads_created,
        errors:        @errors
      )
    end

    private

    def normalize_subreddit(name)
      name.to_s.sub(/\Ar\/+/i, "").strip
    end

    def scraper_prefix
      @scraper_prefix ||= "[RedditScraper w_id=#{@watcher.id} name=#{@watcher.name.to_s.truncate(40).inspect}]"
    end

    def scraper_log(msg, level: :info)
      Rails.logger.public_send(level, "#{scraper_prefix} #{msg}")
    end

    # ── HTTP ────────────────────────────────────────────────────────────────

    def api_get(url, query: {}, delay: REQUEST_DELAY)
      sleep delay

      response = HTTParty.get(url, query: query, headers: HEADERS, timeout: 15)

      retries = 0
      while response.code == 429 && retries < MAX_RETRIES
        wait = RETRY_DELAY_BASE * (2**retries)
        scraper_log(
          "HTTP 429 sleeping #{wait}s (attempt #{retries + 1}/#{MAX_RETRIES}) #{url}",
          level: :warn
        )
        sleep wait
        response = HTTParty.get(url, query: query, headers: HEADERS, timeout: 15)
        retries += 1
      end

      # Still 429 after all retries — mark the subreddit as burned for this run.
      if response.code == 429
        if (m = url.match(%r{/r/([^/?.]+)}))
          @rate_limited_subreddits << m[1]
          scraper_log(
            "subreddit_rate_limited subreddit=#{m[1]} after #{MAX_RETRIES} retries — skipping remaining phrases",
            level: :warn
          )
        end
      end

      response
    end

    # ── Scraping ─────────────────────────────────────────────────────────────

    def scrape(subreddit)
      if @rate_limited_subreddits.include?(subreddit)
        @skipped += 1
        @skipped_rate_limited += 1
        scraper_log("skip rate_limited subreddit=#{subreddit}")
        return
      end

      posts = fetch_posts(subreddit)
      posts.each do |child|
        next unless child["kind"] == "t3"

        process_post(child["data"], subreddit)
      end
    rescue => e
      err = { subreddit: subreddit, message: e.message }
      @errors << err
      scraper_log("scrape_error #{err.inspect}", level: :error)
    end

    # ── Reddit search ─────────────────────────────────────────────────────────

    # Combines all phrases into one OR query so we only make one request per subreddit:
    #   "invoice tool" OR "billing software" OR "chasing clients"
    def fetch_posts(subreddit)
      q   = build_or_query(@phrases)
      p 22222222222222
      p q
      p 22222222222222
      url = "#{BASE_URL}/r/#{CGI.escape(subreddit)}/search.json"
      response = api_get(url, query: {
        q:           q,
        sort:        "new",
        t:           @time_filter,
        limit:       @limit,
        restrict_sr: "true"
      })

      raise "Reddit returned HTTP #{response.code} for r/#{subreddit}" unless response.success?

      children = response.dig("data", "children") || []
      scraper_log(
        "reddit_search r/#{subreddit} q=#{q} " \
        "http=#{response.code} posts_returned=#{children.size}"
      )
      children
    end

    # Quotes multi-word phrases, strips stop-words from each term, joins with OR.
    def build_or_query(phrases)
      terms = phrases.map { |p| strip_stop_words(p) }.reject(&:blank?)
      terms = phrases if terms.empty?
      terms.map { |t| t.include?(" ") ? %("#{t}") : t }.join(" OR ")
    end

    def strip_stop_words(phrase)
      raw    = phrase.to_s.strip
      return raw if raw.blank?

      tokens     = raw.scan(/[\w']+/u).map { |t| t.downcase.delete("'") }.reject { |t| t.length < 2 }
      meaningful = tokens.reject { |t| STOP_WORDS.include?(t) }
      meaningful.join(" ").presence || raw
    end

    # ── Post processing ───────────────────────────────────────────────────────

    def process_post(data, subreddit)
      unless keyword_layer_matches?(data)
        @skipped += 1
        @skipped_keyword_layer += 1
        scraper_log(
          "skip keyword_layer reddit_id=#{data['id']} subreddit=#{subreddit} " \
          "title=#{data['title'].to_s.truncate(120).inspect}"
        )
        return
      end

      raw_post = store_post(data, subreddit)
      return unless raw_post

      permalink = data["permalink"].presence
      fetch_comments(raw_post, permalink) if permalink && data["num_comments"].to_i.positive?

      lead = create_lead(raw_post)
      if lead
        @ai_lead_ids << lead.id
        scraper_log(
          "lead_created lead_id=#{lead.id} raw_post_id=#{raw_post.id} " \
          "title=#{raw_post.title.to_s.truncate(100).inspect}"
        )
      end

      @total_fetched += 1
      scraper_log("progress posts_processed=#{@total_fetched}") if (@total_fetched % 25).zero?
    end

    # Layer 1 (Ruby): full watcher keyword list vs title + body before DB / AI.
    def keyword_layer_matches?(data)
      body = data["selftext"]
      body = "" if body.blank? || body.in?(%w[[deleted] [removed]])
      post = Struct.new(:title, :body).new(data["title"].to_s, body.to_s)
      Matchers::KeywordMatcher.matches?(post, @watcher.keywords)
    end

    # ── AI flush ──────────────────────────────────────────────────────────────

    def flush_ai_reviews
      return if @ai_lead_ids.blank?

      unless Analyzers::LeadRelevanceAnalyzer.api_key?
        scraper_log(
          "no_anthropic_key — approve_without_ai lead_ids=#{@ai_lead_ids.inspect} (#{@ai_lead_ids.size} leads)"
        )
        Analyzers::LeadRelevanceAnalyzer.approve_without_ai!(@ai_lead_ids)
        return
      end

      batch_size = Analyzers::LeadRelevanceAnalyzer::BATCH_SIZE
      slices     = @ai_lead_ids.each_slice(batch_size).to_a
      scraper_log(
        "enqueue_ai_batches lead_count=#{@ai_lead_ids.size} batch_size=#{batch_size} " \
        "batches=#{slices.size} lead_ids=#{@ai_lead_ids.inspect}"
      )
      slices.each { |slice| AnalyzeLeadRelevanceBatchJob.perform_later(slice) }
    end

    # ── Post storage ──────────────────────────────────────────────────────────

    def store_post(data, subreddit)
      reddit_id = data["id"]

      if RawPost.exists?(source: "reddit", external_id: reddit_id)
        @skipped += 1
        @skipped_duplicate_post += 1
        scraper_log("skip duplicate_post reddit_id=#{reddit_id}")
        return nil
      end

      body = data["selftext"]
      body = nil if body.blank? || body.in?(%w[[deleted] [removed]])

      post = RawPost.create!(
        source:        "reddit",
        external_id:   reddit_id,
        title:         data["title"],
        body:          body,
        url:           data["url"]&.start_with?("http") ? data["url"] : "#{BASE_URL}#{data["permalink"]}",
        upvotes:       data["score"],
        comment_count: data["num_comments"],
        scraped_at:    Time.current,
        metadata: {
          subreddit:    subreddit,
          author:       data["author"],
          created_utc:  data["created_utc"],
          upvote_ratio: data["upvote_ratio"]
        }
      )
      @saved += 1
      scraper_log(
        "raw_post_saved id=#{post.id} reddit_id=#{reddit_id} " \
        "upvotes=#{post.upvotes} comments=#{post.comment_count} " \
        "title=#{post.title.to_s.truncate(100).inspect}"
      )
      post
    rescue ActiveRecord::RecordNotUnique
      @skipped += 1
      @skipped_duplicate_post += 1
      scraper_log("skip duplicate_post race reddit_id=#{reddit_id}", level: :warn)
      nil
    end

    # ── Lead creation ─────────────────────────────────────────────────────────

    def create_lead(raw_post)
      lead = Lead.create!(
        watcher:  @watcher,
        raw_post: raw_post,
        score:    LeadScoring.base_score(raw_post, @watcher),
        status:   "new"
      )
      @leads_created += 1
      lead
    rescue ActiveRecord::RecordNotUnique
      @skipped += 1
      @skipped_duplicate_lead += 1
      scraper_log(
        "skip duplicate_lead raw_post_id=#{raw_post.id} reddit_id=#{raw_post.external_id}",
        level: :warn
      )
      nil
    end

    # ── Comments ──────────────────────────────────────────────────────────────

    def fetch_comments(raw_post, permalink)
      path     = permalink.start_with?("/") ? permalink : "/#{permalink}"
      url      = "#{BASE_URL}#{path}.json"
      response = api_get(url, query: { limit: 50, depth: MAX_COMMENT_DEPTH, sort: "top" })

      unless response.success?
        scraper_log(
          "comments_http_error raw_post_id=#{raw_post.id} http=#{response.code}",
          level: :warn
        )
        return
      end

      parsed = response.parsed_response
      parsed = JSON.parse(response.body) if parsed.is_a?(String)
      return unless parsed.is_a?(Array)

      comment_listing = parsed[1]
      return unless comment_listing

      top_level = comment_listing.dig("data", "children") || []
      top_level.each { |child| store_comment_tree(raw_post, child, depth: 0) }
      scraper_log(
        "comments_stored raw_post_id=#{raw_post.id} " \
        "reddit_id=#{raw_post.external_id} rows=#{raw_post.post_comments.count}"
      )
    rescue => e
      scraper_log(
        "comments_fetch_error raw_post_id=#{raw_post.id} #{e.class}: #{e.message}",
        level: :warn
      )
    end

    def store_comment_tree(raw_post, node, depth:)
      return if depth > MAX_COMMENT_DEPTH
      return if node["kind"] == "more"
      return unless node["kind"] == "t1"

      data = node["data"]
      body = data["body"]
      return if body.blank? || body.in?(%w[[deleted] [removed]])

      save_comment(raw_post, data, depth: depth)

      replies  = data["replies"]
      children = replies.is_a?(Hash) ? replies.dig("data", "children") : []
      Array(children).each { |child| store_comment_tree(raw_post, child, depth: depth + 1) }
    end

    def save_comment(raw_post, data, depth:)
      PostComment.create!(
        raw_post:   raw_post,
        comment_id: data["id"],
        body:       data["body"],
        score:      data["score"].to_i,
        depth:      depth
      )
    rescue ActiveRecord::RecordNotUnique
      # already stored — safe to skip
    end
  end
end
