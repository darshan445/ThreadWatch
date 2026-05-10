# frozen_string_literal: true
module Scrapers
  # Asks Gemini to evaluate a batch of raw Reddit posts for relevance to a watcher.
  # Only title + body are sent — comments are NOT fetched yet; that happens only
  # for posts that pass this filter (after keyword pre-filter in RedditScraper).
  #
  # Returns [{ post_data:, ai_reason:, ai_confidence: }] for relevant posts.
  # ai_confidence is 1–10 and feeds directly into LeadScoring (75% weight).
  class PostRelevanceChecker
    BATCH_SIZE     = 5
    MAX_BODY_LEN   = 500
    MIN_CONFIDENCE = 5   # 1–10 scale; posts scoring below this are rejected

    SYSTEM_PROMPT = <<~TXT.squish
      You are a strict lead qualifier for a product business.
      Your job: decide whether each Reddit post author is RIGHT NOW experiencing
      the EXACT problem the described product solves — not a similar or adjacent problem.
      Default is false. Only mark true when you are highly confident.
      Partial matches, same industry but different pain, beginner questions = false.
      When in doubt = false.
      Output a JSON array only. No markdown. No text outside the array.
    TXT

    def self.filter(posts_data, watcher)
      new(watcher).filter(posts_data)
    end

    def initialize(watcher)
      @watcher = watcher
    end

    # Returns [{ post_data: Hash, ai_reason: String|nil, ai_confidence: Integer }, ...]
    def filter(posts_data)
      # return accept_all(posts_data) unless GeminiClient.api_key?
      return [] if posts_data.empty?

      posts_data.each_slice(BATCH_SIZE).flat_map { |batch| check_batch(batch) }
    end

    private

    def check_batch(batch)
      Rails.logger.info "[PostRelevanceChecker] Sending #{batch.size} posts to Gemini for watcher=#{@watcher.name.inspect}"

      raw = GeminiClient.generate(
        system:      SYSTEM_PROMPT,
        user:        build_prompt(batch),
        max_tokens:  800,
        temperature: 0.1
      )

      Rails.logger.debug "[PostRelevanceChecker] Gemini raw: #{raw.truncate(600)}"

      results  = parse_response(raw, batch)
      Rails.logger.info "[PostRelevanceChecker] #{results.size}/#{batch.size} posts accepted"
      results
    rescue => e
      Rails.logger.warn "[PostRelevanceChecker] Gemini error — accepting batch: #{e.message}"
      # accept_all(batch)
    end

    def build_prompt(posts_data)
      entries = posts_data.each_with_index.map do |p, i|
        body = p["selftext"].to_s
        body = "" if body.in?(%w[[deleted] [removed]])
        <<~ENTRY.strip
          POST #{i + 1} | id=#{p["id"]}
          Title: #{p["title"]}
          Body: #{body.truncate(MAX_BODY_LEN).presence || "(none)"}
        ENTRY
      end.join("\n\n---\n\n")

      <<~PROMPT
        ══ PRODUCT ════════════════════════════════════════════════════════════════
        Name:        #{@watcher.name}
        Description: #{@watcher.description.to_s.strip.presence || "(not provided)"}
        Keywords:    #{@watcher.keywords}

        Before evaluating posts, derive from the description:
        A) TARGET CUSTOMER — who exactly is this built for?
        B) EXACT PROBLEM   — the one specific pain point this product solves
        C) NON-CUSTOMERS   — who seems related but is NOT the right customer?

        ══ DISQUALIFICATION RULES (mark false + confidence=0 if ANY apply) ══════
        • Author's platform/tool/business type doesn't match TARGET CUSTOMER
        • Pain is in the same industry but is a DIFFERENT problem than EXACT PROBLEM
        • Post is a recommendation request, beginner question, or advice-seeking
        • Author already has a solution and is just optimising
        • No clear, direct evidence of EXACT PROBLEM in the post text
        • Any doubt at all

        ══ CONFIDENCE SCALE (1–10, only for relevant=true posts) ════════════════
        1–3  weak:    topic overlap but pain is vague or indirect
        4–6  moderate: clear pain, could be solved by several products
        7–9  strong:  specific pain this product directly solves
        10   perfect: post reads like a use-case for exactly this product

        ══ POSTS ═════════════════════════════════════════════════════════════════
        #{entries}

        ══ OUTPUT ════════════════════════════════════════════════════════════════
        One JSON object per post, same order. "reason" ≤ 12 words: quote the exact
        pain phrase if true, or state the specific disqualification if false.
        confidence is 1–10 for true, 0 for false.

        [{"post_id":"<id>","relevant":true|false,"confidence":<0-10>,"reason":"<≤12 words>"},...]
      PROMPT
    end

    def parse_response(raw, posts_data)
      clean = raw.strip
                 .sub(/\A```(?:json)?\r?\n?/i, "")
                 .sub(/\r?\n?```\z/m, "")
                 .strip

      parsed = JSON.parse(clean)
      raise "expected JSON array, got #{parsed.class}" unless parsed.is_a?(Array)

      index = posts_data.index_by { |p| p["id"] }

      parsed.each do |r|
        confidence = r["confidence"].to_i
        accepted   = r["relevant"] == true && confidence >= MIN_CONFIDENCE
        verdict    = accepted ? "✅ ACCEPT" : "❌ REJECT"
        Rails.logger.info "[PostRelevanceChecker] #{verdict} id=#{r["post_id"]} " \
                          "confidence=#{confidence}/10 — #{r["reason"]}"
      end

      parsed.filter_map do |r|
        confidence = r["confidence"].to_i
        next unless r["relevant"] == true && confidence >= MIN_CONFIDENCE

        post_data = index[r["post_id"].to_s]
        next unless post_data

        { post_data: post_data, ai_reason: r["reason"].to_s.presence, ai_confidence: confidence }
      end
    rescue => e
      Rails.logger.warn "[PostRelevanceChecker] parse error — accepting batch: #{e.message}"
      # accept_all(posts_data)
    end

    def accept_all(posts_data)
      posts_data.map { |p| { post_data: p, ai_reason: nil, ai_confidence: nil } }
    end
  end
end
