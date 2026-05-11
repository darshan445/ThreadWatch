# frozen_string_literal: true

module Scrapers
  # Orchestrates the full scraping pipeline for one watcher run.
  #
  # Pipeline per subreddit × phrase:
  #   1. Search Reddit        — fetch post data (title + body only)
  #   2. Keyword pre-filter   — cheap word-overlap check, no API calls
  #   3. Find-or-create post  — RawPost stored once globally (deduplicated by external_id)
  #   4. Lead existence check — if a Lead already exists for this watcher+post, skip it
  #   5. AI relevance filter  — Gemini scores relevance (confidence 1-10)
  #   6. Fetch comments       — only for AI-accepted posts
  #   7. Create lead          — unique on (watcher_id, raw_post_id); DB constraint is safety net
  #
  # Schema relationships:
  #   RawPost (global, one per Reddit post)
  #     └─ has_many :leads
  #     └─ has_many :watchers, through: :leads
  #   Lead (scoped per watcher — unique on watcher_id + raw_post_id)
  #
  class RedditScraper
    MAX_LIMIT    = 100
    TIME_FILTERS = %w[hour day week month year all].freeze

    STOP_WORDS = %w[
      a an the is are was were be been being to of and or but if in on at for
      with from as it its we you he she they them this that these those i id ill
      ive im youre your my our their what which who how why when where there here
      dont cant wont isnt arent wasnt werent hasnt havent hadnt does did doing done
    ].freeze

    Result = Struct.new(:saved, :skipped, :leads_created, :errors, keyword_init: true) do
      def total    = saved + skipped
      def success? = errors.empty?
    end

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
      @api         = RedditApiClient.new

      @saved = @skipped = @leads_created = 0
      @errors = []
    end

    def call
      log "start subreddits=#{@subreddits.inspect} phrases=#{@phrases.inspect} " \
          "limit=#{@limit} time_filter=#{@time_filter}"

      @subreddits.each do |subreddit|
        @phrases.each { |phrase| scrape(subreddit, phrase) }
      end

      @watcher.update_column(:last_checked_at, Time.current)

      log "done saved=#{@saved} skipped=#{@skipped} leads_created=#{@leads_created} errors=#{@errors.size}"

      Result.new(saved: @saved, skipped: @skipped, leads_created: @leads_created, errors: @errors)
    end

    private

    # ── Pipeline ──────────────────────────────────────────────────────────────

    def scrape(subreddit, phrase)
      if @api.subreddit_burned?(subreddit)
        log "skip burned_subreddit=#{subreddit} phrase=#{phrase.inspect}"
        return
      end

      q     = strip_stop_words(phrase)
      posts = @api.search_posts(subreddit, q, sort: "new",
                                             time_filter: @time_filter,
                                             limit: @limit)

      # 1. Keyword pre-filter
      kw_passed, kw_skipped = posts.partition { |p| Matchers::KeywordMatcher.matches?(p, @watcher) }
      kw_skipped.each { |p| log "kw_skip id=#{p["id"]} title=#{p["title"].to_s.truncate(80).inspect}" }
      log "search r/#{subreddit} q=#{q.inspect} returned=#{posts.size} " \
          "kw_passed=#{kw_passed.size} kw_skipped=#{kw_skipped.size}"
      return if kw_passed.empty?

      # 2. Find-or-create RawPost for every keyword-passing post
      raw_posts_map = build_raw_posts_map(kw_passed, subreddit)

      # 3. Skip posts that already have a lead for this watcher
      needs_ai, already_led = kw_passed.partition do |p|
        rp = raw_posts_map[p["id"]]
        rp && !lead_exists_for_watcher?(rp)
      end

      already_led.each do |p|
        log "lead_exists_skip id=#{p["id"]} — lead already created for this watcher"
        @skipped += 1
      end

      log "lead_check r/#{subreddit} needs_ai=#{needs_ai.size} already_led=#{already_led.size}"
      return if needs_ai.empty?

      # 4. AI relevance filter (Gemini)
      relevant = PostRelevanceChecker.filter(needs_ai, @watcher)
      log "ai_filter r/#{subreddit} sent=#{needs_ai.size} ai_relevant=#{relevant.size}"

      # 5. Fetch comments + create lead for each relevant post
      relevant.each do |r|
        raw_post = raw_posts_map[r[:post_data]["id"]]
        next unless raw_post

        nodes = @api.fetch_comment_nodes(r[:post_data]["permalink"].to_s)
        store_comments(raw_post, nodes)
        create_lead(raw_post, ai_reason: r[:ai_reason], ai_confidence: r[:ai_confidence])
      end
    rescue => e
      err = { subreddit: subreddit, phrase: phrase, message: e.message }
      @errors << err
      log "scrape_error #{err.inspect}", level: :error
    end

    # ── RawPost: find-or-create (one global record per Reddit post) ────────────

    def build_raw_posts_map(posts_data, subreddit)
      posts_data.each_with_object({}) do |data, map|
        rp = find_or_create_raw_post(data, subreddit)
        map[data["id"]] = rp if rp
      end
    end

    def find_or_create_raw_post(data, subreddit)
      reddit_id = data["id"]
      existing  = RawPost.find_by(source: "reddit", external_id: reddit_id)

      if existing
        log "post_exists id=#{existing.id} reddit_id=#{reddit_id}"
        return existing
      end

      body = data["selftext"].to_s
      body = nil if body.blank? || body.in?(%w[[deleted] [removed]])

      post = RawPost.create!(
        source:        "reddit",
        external_id:   reddit_id,
        title:         data["title"],
        body:          body,
        url:           data["url"]&.start_with?("http") ? data["url"] : "#{RedditApiClient::BASE_URL}#{data["permalink"]}",
        upvotes:       data["score"],
        comment_count: data["num_comments"],
        posted_at:     data["created_utc"].present? ? Time.at(data["created_utc"].to_i).utc : nil,
        scraped_at:    Time.current,
        metadata: {
          subreddit:    subreddit,
          author:       data["author"],
          upvote_ratio: data["upvote_ratio"]
        }
      )
      @saved += 1
      log "post_created id=#{post.id} reddit_id=#{reddit_id} title=#{post.title.to_s.truncate(80).inspect}"
      post
    rescue ActiveRecord::RecordNotUnique
      RawPost.find_by(source: "reddit", external_id: reddit_id)
    end

    # ── Lead existence check ───────────────────────────────────────────────────

    # True when a Lead already exists for this watcher+post — no need to call AI again.
    def lead_exists_for_watcher?(raw_post)
      Lead.exists?(watcher_id: @watcher.id, raw_post_id: raw_post.id)
    end

    # ── Comments ──────────────────────────────────────────────────────────────

    def store_comments(raw_post, nodes)
      nodes.each { |node| store_comment_tree(raw_post, node, depth: 0) }
      log "comments_stored raw_post_id=#{raw_post.id} count=#{raw_post.post_comments.count}"
    rescue => e
      log "comments_error raw_post_id=#{raw_post.id} #{e.class}: #{e.message}", level: :warn
    end

    def store_comment_tree(raw_post, node, depth:)
      return if depth > RedditApiClient::MAX_COMMENT_DEPTH
      return if node["kind"] == "more"
      return unless node["kind"] == "t1"

      data = node["data"]
      body = data["body"].to_s
      return if body.blank? || body.in?(%w[[deleted] [removed]])

      PostComment.create!(
        raw_post:   raw_post,
        comment_id: data["id"],
        body:       body,
        score:      data["score"].to_i,
        depth:      depth
      )

      replies  = data["replies"]
      children = replies.is_a?(Hash) ? replies.dig("data", "children") : []
      Array(children).each { |child| store_comment_tree(raw_post, child, depth: depth + 1) }
    rescue ActiveRecord::RecordNotUnique
      # duplicate comment — skip silently
    end

    # ── Lead ──────────────────────────────────────────────────────────────────

    def create_lead(raw_post, ai_reason:, ai_confidence:)
      lead = Lead.create!(
        watcher:        @watcher,
        raw_post:       raw_post,
        status:         "new",
        ai_match:       true,
        ai_reason:      ai_reason,
        ai_confidence:  ai_confidence,
        ai_reviewed_at: Time.current,
        score:          LeadScoring.total_score(raw_post, ai_confidence: ai_confidence)
      )
      @leads_created += 1
      log "lead_created id=#{lead.id} score=#{lead.score} title=#{raw_post.title.to_s.truncate(80).inspect}"
      lead
    rescue ActiveRecord::RecordNotUnique
      @skipped += 1
      log "lead_duplicate_skip raw_post_id=#{raw_post.id}", level: :warn
      nil
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def strip_stop_words(phrase)
      raw        = phrase.to_s.strip
      tokens     = raw.scan(/[\w']+/u).map { |t| t.downcase.delete("'") }.reject { |t| t.length < 2 }
      meaningful = tokens.reject { |t| STOP_WORDS.include?(t) }
      meaningful.join(" ").presence || raw
    end

    def normalize_subreddit(name)
      name.to_s.sub(/\Ar\/+/i, "").strip
    end

    def log(msg, level: :info)
      prefix = "[RedditScraper w=#{@watcher.id} #{@watcher.name.to_s.truncate(30).inspect}]"
      Rails.logger.public_send(level, "#{prefix} #{msg}")
    end
  end
end
