# frozen_string_literal: true

module Analyzers
  # AI prompt for auto-generating watcher keywords and subreddit candidates from a description.
  # System prompt is intentionally generic; all business context goes in the user message.
  class WatcherSetupPrompt
    SYSTEM_PROMPT = <<~TXT.squish
      You are an expert Reddit lead-generation strategist for product businesses.
      Your job: given a product description, produce the exact search configuration
      needed to surface Reddit posts where real potential customers vent about the
      specific problem this product solves.
      Be precise. Generic or broad terms waste API calls and produce noise.
      Return JSON only. No markdown, no explanation.
    TXT

    MAX_KEYWORDS          = 5
    MAX_SUBREDDIT_QUERIES = 8

    class << self
      # Returns { keywords: "kw1, kw2, ...", subreddit_queries: ["q1", "q2", ...] }
      # or raises on parse failure.
      def generate(watcher)
        user_message = build_user_message(watcher)
        Rails.logger.info "[WatcherSetupPrompt] user_message=#{user_message.truncate(600).inspect}"
        user_message
      end

      def build_user_message(watcher)
        desc = watcher.description.to_s.strip.presence || watcher.name.to_s.strip

        <<~TXT.strip
          Business name: #{watcher.name}
          Description: #{desc}

          Generate Reddit monitoring configuration to find posts where potential customers
          are actively describing the SPECIFIC PAIN this product solves.

          ── KEYWORDS (exactly #{MAX_KEYWORDS} phrases) ──────────────────────────────────
          Rules:
          • Each phrase is something a frustrated potential customer would literally type
            in a Reddit post title or body — conversational, raw, complaint-style language.
          • The phrase must reflect the SPECIFIC pain this product addresses, not the
            product category. Bad: "invoice tool". Good: "clients won't pay invoice".
          • 2–5 words per phrase. No jargon, no product names, no generic nouns alone.
          • Ask yourself: "Would someone who desperately needs this product type this phrase
            in a Reddit rant or question?" If yes — include it.

          ── SUBREDDIT SEARCH TERMS (exactly #{MAX_SUBREDDIT_QUERIES} terms) ─────────────
          Rules:
          • These are short search queries (1–3 words) used to DISCOVER subreddits —
            not the subreddit names themselves.
          • Target communities where the TARGET BUYER of this product actually posts:
            their profession, their industry, their workflow, their tools.
          • Mix: direct audience communities + adjacent problem communities.
          • Ask yourself: "Where on Reddit would the person who has this pain spend time?"

          Output exactly this JSON (arrays of strings, nothing else):
          {
            "keywords": ["phrase 1", "phrase 2", ...],
            "subreddit_queries": ["query 1", "query 2", ...]
          }
        TXT
      end

      # Parse and validate the raw JSON string returned by the AI.
      # Returns { keywords: String, subreddit_queries: Array<String> } or raises.
      def parse_response(raw_text)
        clean = raw_text.to_s.strip
        # Strip markdown code fences if present
        clean = clean.sub(/\A```(?:json)?\r?\n?/i, "").sub(/\r?\n?```\z/m, "").strip

        parsed = JSON.parse(clean)

        unless parsed.is_a?(Hash)
          raise "expected JSON object, got #{parsed.class}"
        end

        keywords = Array(parsed["keywords"]).map(&:to_s).map(&:strip).reject(&:blank?).first(MAX_KEYWORDS)
        subreddit_queries = Array(parsed["subreddit_queries"]).map(&:to_s).map(&:strip).reject(&:blank?).first(MAX_SUBREDDIT_QUERIES)

        if keywords.empty?
          raise "AI returned no keywords"
        end

        {
          keywords:          keywords.join(", "),
          subreddit_queries: subreddit_queries
        }
      rescue JSON::ParserError => e
        raise "JSON parse error — #{e.message} | raw: #{raw_text.to_s.truncate(400)}"
      end
    end
  end
end
