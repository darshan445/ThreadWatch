# frozen_string_literal: true

# Lead #score (max 100):
#
#   AI relevance  — 75 pts  → (ai_confidence / 10.0) * 75
#                             ai_confidence is 1–10 from Gemini (PostRelevanceChecker)
#                             nil/0 confidence → 0 AI pts
#
#   Engagement    — 25 pts  → upvotes (10) + comment count (10) + recency (5)
#
module LeadScoring
  AI_MAX         = 75
  CONFIDENCE_MAX = 10
  ENGAGEMENT_MAX = 25

  module_function

  # ai_confidence: Integer 1–10 (or nil when Gemini was skipped / fallback)
  def total_score(raw_post, ai_confidence:)
    ai_points(ai_confidence) + engagement_points(raw_post)
  end

  def ai_points(confidence)
    return 0 unless confidence.to_i > 0
    ((confidence.to_i.clamp(1, CONFIDENCE_MAX) / CONFIDENCE_MAX.to_f) * AI_MAX).round
  end

  # Up to 25 pts split across upvotes, comments, and post freshness.
  def engagement_points(raw_post)
    e = 0
    e += [raw_post.upvotes.to_i, 10].min
    e += [raw_post.comment_count.to_i * 2, 10].min

    if raw_post.posted_at.present?
      hours = (Time.current - raw_post.posted_at) / 3600
      e += if    hours < 2  then 5
             elsif hours < 6  then 3
             elsif hours < 24 then 1
             else                  0
             end
    end

    [e, ENGAGEMENT_MAX].min
  end
end
