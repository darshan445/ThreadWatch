# frozen_string_literal: true

module Analyzers
  # AI prompt for auto-generating watcher keywords and subreddit candidates from a description.
  # System prompt is intentionally generic; all business context goes in the user message.
  class WatcherSetupPrompt
    SYSTEM_PROMPT = <<~TXT.squish
      You are a Reddit growth tool that generates monitoring configuration for a SaaS/product business.
      Return JSON only. No markdown, no explanation.
    TXT

    MAX_KEYWORDS         = 5
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

          Generate Reddit monitoring configuration:

          1. Exactly #{MAX_KEYWORDS} keyword phrases (2–4 natural words each).
             Focus on pain-point statements and buying signals people actually type on Reddit.
             Avoid generic single words. Good examples: "chasing payment", "clients not paying", "late invoice".

          2. #{MAX_SUBREDDIT_QUERIES} subreddit search terms (1–2 words each) to discover the most relevant communities.
             Think broadly: audience communities, topic communities, competitor/industry communities.

          Output exactly this JSON structure (arrays of strings):
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
