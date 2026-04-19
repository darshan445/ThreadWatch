# frozen_string_literal: true

# Lead #score (max 100): 1) AI fit  2) keyword fit  3) Reddit engagement
module LeadScoring
  AI_MAX         = 50
  KEYWORD_MAX    = 35
  ENGAGEMENT_MAX = 15

  module_function

  # New lead — AI not reviewed yet (ai_match nil): keyword + engagement only.
  def base_score(raw_post, watcher)
    total_score(raw_post, watcher, ai_match: nil)
  end

  # ai_match: true / false / nil (treated like false for AI points until reviewed).
  def total_score(raw_post, watcher, ai_match:)
    post = Struct.new(:title, :body).new(raw_post.title.to_s, raw_post.body.to_s)
    rel  = Matchers::KeywordMatcher.relevance_score(post, watcher.keywords)
    kw   = (rel * KEYWORD_MAX / 100.0).round
    eng  = engagement_points(raw_post)
    ai   = ai_points(ai_match)

    (ai + kw + eng).clamp(0, 100)
  end

  def ai_points(ai_match)
    ai_match == true ? AI_MAX : 0
  end

  def keyword_points(raw_post, watcher)
    post = Struct.new(:title, :body).new(raw_post.title.to_s, raw_post.body.to_s)
    rel  = Matchers::KeywordMatcher.relevance_score(post, watcher.keywords)
    (rel * KEYWORD_MAX / 100.0).round
  end

  # Tertiary: Reddit activity + freshness (capped; one recency tier).
  def engagement_points(raw_post)
    e = 0
    e += [raw_post.upvotes.to_i, 6].min
    e += [raw_post.comment_count.to_i * 2, 6].min

    created_utc = raw_post.metadata&.dig("created_utc").to_i
    if created_utc.positive?
      hours = (Time.current.to_i - created_utc) / 3600
      e += if hours < 2
             3
           elsif hours < 6
             2
           elsif hours < 24
             1
           else
             0
           end
    end

    [e, ENGAGEMENT_MAX].min
  end
end
