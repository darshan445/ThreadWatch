# frozen_string_literal: true

module Matchers
  # Layer 1: cheap keyword gate on title + body. Any comma-separated phrase may match;
  # multi-word phrases require every word to match (with light suffix stemming).
  class KeywordMatcher
    def self.matches?(post, keywords_string)
      new(post, keywords_string).matches?
    end

    # 0–100: average strength across comma-separated phrases (title hits score higher).
    def self.relevance_score(post, keywords_string)
      new(post, keywords_string).relevance_score
    end

    def initialize(post, keywords_string)
      @title = post.title.to_s.downcase.strip
      @body  = post.body.to_s.downcase.strip
      @text  = [@title, @body].join(" ").strip
      @keywords = parse_keywords(keywords_string)
    end

    def matches?
      return true if @keywords.empty?

      @keywords.any? { |keyword| keyword_present?(keyword, @text) }
    end

    def relevance_score
      return 100 if @keywords.empty?

      parts = @keywords.map { |kw| phrase_match_strength(kw) }
      (parts.sum.to_f / parts.size).round.clamp(0, 100)
    end

    private

    def phrase_match_strength(phrase)
      return 0 unless keyword_present?(phrase, @text)

      words = phrase.split(/\s+/).reject(&:blank?)
      return 0 if words.empty?

      all_in_title = @title.present? && words.all? { |w| text_contains_word_in?(w, @title) }
      return 100 if all_in_title

      any_in_title = @title.present? && words.any? { |w| text_contains_word_in?(w, @title) }
      return 88 if any_in_title

      72
    end

    def parse_keywords(keywords_string)
      keywords_string.to_s
                     .split(",")
                     .map(&:strip)
                     .map(&:downcase)
                     .reject(&:blank?)
    end

    def keyword_present?(keyword, haystack)
      words = keyword.split(/\s+/).reject(&:blank?)
      return false if words.empty?

      words.all? { |word| text_contains_word_in?(word, haystack) }
    end

    def text_contains_word_in?(word, haystack)
      return false if word.blank? || haystack.blank?

      return true if haystack.include?(word)

      stem = stem_word(word)
      return false if stem.blank? || stem.length < 2

      haystack.split(/\W+/).any? do |text_word|
        tw = text_word.downcase
        next false if tw.blank?

        stem_word(tw).start_with?(stem)
      end
    end

    def stem_word(word)
      word.to_s
          .downcase
          .gsub(/(?:ing|tion|tions|ed|er|ers|es|ly|s)\z/, "")
    end
  end
end
