# frozen_string_literal: true

module Scrapers
  # Orchestrates the full scraping pipeline for one watcher run.
  #
  # Pipeline per subreddit × phrase:
  #   1. Search Reddit   — returns raw post data (title/body only)
  #   2. Keyword filter  — cheap pre-screen, no API calls
  #   3. Find-or-create  — RawPost stored for every keyword-passing post
  #   4. Processed gate  — skip posts this watcher already evaluated (WatcherPost.processed)
  #   5. AI filter       — Gemini decides relevance + confidence 1-10
  #   6. Mark processed  — WatcherPost.processed=true for ALL posts that reached AI
  #   7. Fetch comments  — only for AI-relevant posts
  #   8. Create lead     — stores Lead with score
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

    # ── Pipeline steps ────────────────────────────────────────────────────────

    def scrape(subreddit, phrase)
      if @api.subreddit_burned?(subreddit)
        log "skip burned_subreddit=#{subreddit} phrase=#{phrase.inspect}"
        return
      end

      q     = strip_stop_words(phrase)
      posts = @api.search_posts(subreddit, q, sort: "new",
                                             time_filter: @time_filter,
                                             limit: @limit)

      # ── Step 1: keyword pre-filter ─────────────────────────────────────────
      kw_passed, kw_skipped = posts.partition { |p| Matchers::KeywordMatcher.matches?(p, @watcher) }
      kw_skipped.each { |p| log "kw_skip id=#{p["id"]} title=#{p["title"].to_s.truncate(80).inspect}" }

      log "search r/#{subreddit} q=#{q.inspect} returned=#{posts.size} " \
          "kw_passed=#{kw_passed.size} kw_skipped=#{kw_skipped.size}"

      return if kw_passed.empty?

      # ── Step 2: find-or-create RawPosts for every keyword-passing post ─────
      raw_posts_by_ext_id = build_raw_posts_map(kw_passed, subreddit)

      # ── Step 3: skip posts this watcher already processed ─────────────────
      to_check, already_done = kw_passed.partition do |p|
        rp = raw_posts_by_ext_id[p["id"]]
        rp && !watcher_post_processed?(rp)
      end

      already_done.each do |p|
        log "watcher_skip id=#{p["id"]} already_processed_for_this_watcher"
        @skipped += 1
      end

      log "watcher_filter r/#{subreddit} to_check=#{to_check.size} already_done=#{already_done.size}"

      return if to_check.empty?

      # ── Step 4: AI relevance filter ────────────────────────────────────────
      relevant = PostRelevanceChecker.filter(to_check, @watcher)

      log "ai_filter r/#{subreddit} sent=#{to_check.size} ai_relevant=#{relevant.size}"

      # ── Step 5: mark ALL checked posts as processed (avoids re-running AI) ─
      to_check.each { |p| mark_watcher_post_processed!(raw_posts_by_ext_id[p["id"]]) }

      # ── Step 6: fetch comments + create leads for AI-relevant posts ─────────
      relevant.each do |r|
        raw_post = raw_posts_by_ext_id[r[:post_data]["id"]]
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

    # ── RawPost find-or-create ─────────────────────────────────────────────────

    # Returns a Hash of { reddit_external_id => RawPost } for all keyword-passing posts.
    # Creates new RawPost records for unseen posts; reuses existing ones for duplicates.
    def build_raw_posts_map(posts_data, subreddit)
      posts_data.each_with_object({}) do |data, map|
        rp = find_or_create_raw_post(data, subreddit)
        map[data["id"]] = rp if rp
      end
    end

    def find_or_create_raw_post(data, subreddit)
      reddit_id = data["id"]

      existing = RawPost.find_by(source: "reddit", external_id: reddit_id)
      if existing
        log "post_found id=#{existing.id} reddit_id=#{reddit_id}"
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
        scraped_at:    Time.current,
        metadata: {
          subreddit:    subreddit,
          author:       data["author"],
          created_utc:  data["created_utc"],
          upvote_ratio: data["upvote_ratio"]
        }
      )
      @saved += 1
      log "post_stored id=#{post.id} reddit_id=#{reddit_id} title=#{post.title.to_s.truncate(80).inspect}"
      post
    rescue ActiveRecord::RecordNotUnique
      # Race condition: another job stored it first — fetch and return it
      RawPost.find_by(source: "reddit", external_id: reddit_id)
    end

    # ── WatcherPost tracking ───────────────────────────────────────────────────

    def watcher_post_processed?(raw_post)
      WatcherPost.exists?(watcher_id: @watcher.id, raw_post_id: raw_post.id, processed: true)
    end

    def mark_watcher_post_processed!(raw_post)
      return unless raw_post

      WatcherPost.upsert(
        { watcher_id: @watcher.id, raw_post_id: raw_post.id, processed: true,
          created_at: Time.current, updated_at: Time.current },
        unique_by: %i[watcher_id raw_post_id],
        update_only: %i[processed updated_at]
      )
    rescue => e
      log "watcher_post_error raw_post_id=#{raw_post.id} #{e.message}", level: :warn
    end

    # ── Storage ───────────────────────────────────────────────────────────────

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
      # duplicate comment from a previous run — skip silently
    end

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
      log "skip duplicate_lead raw_post_id=#{raw_post.id}", level: :warn
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
