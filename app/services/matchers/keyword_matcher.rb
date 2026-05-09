# frozen_string_literal: true

module Matchers
  # Lightweight pre-filter that checks whether a Reddit post's title + body
  # contain enough significant words from at least one of the watcher's keyword
  # phrases. This runs BEFORE the Gemini AI call to avoid burning API quota on
  # posts that share none of the target vocabulary.
  #
  # Matching strategy:
  #   - Tokenise the post content into lowercase word stems.
  #   - For each keyword phrase, extract its significant words (ignore stop-words
  #     and very short tokens).
  #   - A phrase "matches" when ≥ MATCH_THRESHOLD fraction of its significant
  #     words are present in the content (prefix/stem match so "invoice" matches
  #     "invoicing", "invoiced", "invoices").
  #   - The post passes when at least one phrase matches.
  #
  # This is intentionally lenient — it is a coarse gate, not a precise scorer.
  # The AI step that follows is the precision layer.
  class KeywordMatcher
    # 60 % of a phrase's significant words must be present for it to count.
    MATCH_THRESHOLD = 0.6

    # Minimum stem length used for prefix matching (avoids over-matching short
    # stems like "re" from "return").
    MIN_STEM_LEN = 4

    STOP_WORDS = %w[
      a an the is are was were be been being to of and or but if in on at for
      with from as it its we you he she they them this that these those
      i my our your their what which who how why when where there here
      just need help want looking trying using used use can should would could
      will get got getting do does did doing done have has had not no any some
      all also more too very go going went make made think know like feel
      im ive dont cant wont isnt arent wasnt werent hasnt havent hadnt
      ve ll re s d m
    ].to_set.freeze

    def self.matches?(post_data, watcher)
      new(watcher).matches?(post_data)
    end

    def initialize(watcher)
      @phrases = watcher.keywords_list
    end

    # Returns true if any keyword phrase has sufficient word overlap with the post.
    def matches?(post_data)
      content_tokens = tokenise(build_content(post_data))
      @phrases.any? { |phrase| phrase_matches?(phrase, content_tokens) }
    end

    private

    def build_content(post_data)
      title = post_data["title"].to_s
      body  = post_data["selftext"].to_s
      body  = "" if body.in?(%w[[deleted] [removed]])
      "#{title} #{body}"
    end

    # Tokenise text into a set of lowercased, cleaned word stems.
    def tokenise(text)
      text.downcase
          .scan(/[a-z']+/)
          .map { |w| w.delete("'") }
          .reject { |w| w.length < 2 }
          .to_set
    end

    def phrase_matches?(phrase, content_tokens)
      sig_words = significant_words(phrase)
      return false if sig_words.empty?

      matched = sig_words.count { |w| token_present?(w, content_tokens) }
      (matched.to_f / sig_words.size) >= MATCH_THRESHOLD
    end

    def significant_words(phrase)
      phrase.to_s
            .downcase
            .scan(/[a-z']+/)
            .map { |w| w.delete("'") }
            .reject { |w| w.length < 2 || STOP_WORDS.include?(w) }
    end

    # Exact match OR prefix-stem match (handles plurals and common inflections).
    # e.g. keyword "invoice" matches content tokens "invoicing", "invoiced", "invoices".
    def token_present?(keyword, content_tokens)
      return true if content_tokens.include?(keyword)

      stem = keyword.length > MIN_STEM_LEN ? keyword[0, keyword.length - 1] : nil
      return false unless stem

      content_tokens.any? { |t| t.start_with?(stem) }
    end
  end
end
