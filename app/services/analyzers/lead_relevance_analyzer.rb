# frozen_string_literal: true

module Analyzers
  # Anthropic: thread vs watcher fit. Prompts kept minimal for token cost.
  class LeadRelevanceAnalyzer
    BATCH_SIZE        = 6
    MAX_BODY_CHARS    = 1_200
    MAX_COMMENTS      = 5
    MAX_COMMENT_CHARS = 180
    MODEL             = ENV.fetch("ANTHROPIC_LEAD_MODEL", "claude-haiku-4-5-20251001")

    class << self
      def api_key
        Rails.application.credentials[:anthropic_api_key].presence ||
          Rails.application.credentials.dig(:anthropic, :api_key).presence ||
          ENV["ANTHROPIC_API_KEY"].presence
      end

      def api_key?
        api_key.present?
      end

      def analyze_lead_ids!(lead_ids)
        ids = Array(lead_ids).map(&:to_i).uniq
        return if ids.empty?

        unless api_key?
          approve_without_ai!(ids)
          return
        end

        leads = Lead.where(id: ids).includes(:watcher, raw_post: :post_comments).order(:id)
        return if leads.empty?

        if leads.size == 1
          analyze_one!(leads.first)
        else
          analyze_batch!(leads.to_a)
        end
      end

      private

      def approve_without_ai!(ids)
        Lead.where(id: ids).includes(:watcher, :raw_post).find_each do |lead|
          lead.update_columns(
            ai_match:       true,
            ai_reason:      nil,
            ai_reviewed_at: Time.current,
            score:          LeadScoring.total_score(lead.raw_post, lead.watcher, ai_match: true)
          )
        end
      end

      def client
        @client ||= Anthropic::Client.new(access_token: api_key)
      end

      def analyze_one!(lead)
        user_msg = LeadQualifier.build_prompt(lead, thread_text: compact_thread(lead))
        payload = call_api_raw(LeadQualifier::SYSTEM_PROMPT, user_msg)
        apply_result!(lead, parse_json_object(payload))
      end

      def analyze_batch!(leads)
        user_msg = LeadQualifier.build_batch_prompt(
          leads,
          thread_text_for: ->(l) { compact_thread(l, multiline: false) }
        )
        raw = call_api_raw(LeadQualifier::SYSTEM_PROMPT, user_msg)
        data = parse_json_object(raw)
        results = data["results"]
        raise "batch missing results" unless results.is_a?(Array)

        results.each do |r|
          lid = r["lead_id"].to_i
          lead = leads.find { |l| l.id == lid }
          apply_result!(lead, r) if lead
        end
      end

      def compact_thread(lead, multiline: true)
        post = lead.raw_post
        bits = []
        bits << "T:#{post.title.to_s.truncate(300)}"
        bits << "B:#{post.body.to_s.truncate(MAX_BODY_CHARS)}" if post.body.present?
        comments = post.post_comments.sort_by { |c| -c.score.to_i }.first(MAX_COMMENTS)
        if comments.any?
          cstr = comments.map { |c| "#{c.score}:#{c.body.to_s.truncate(MAX_COMMENT_CHARS)}" }.join(multiline ? " | " : " ")
          bits << "C:#{cstr}"
        end
        sep = multiline ? "\n" : " "
        bits.join(sep)
      end

      def call_api_raw(system, user_content)
        response = client.messages(parameters: {
          model:       MODEL,
          max_tokens:  400,
          system:      system,
          messages:    [{ role: "user", content: user_content }]
        })

        response = response.deep_stringify_keys if response.respond_to?(:deep_stringify_keys)
        response.dig("content", 0, "text").to_s.strip
      end

      def parse_json_object(text)
        clean = text.strip
        if clean.start_with?("```")
          clean = clean.sub(/\A```(?:json)?\r?\n?/i, "")
          clean = clean.sub(/\r?\n?```[\s\S]*\z/m, "")
          clean = clean.strip
        end
        parsed = JSON.parse(clean)
        raise "expected JSON object" unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError => e
        raise "JSON parse error — #{e.message} | raw: #{text.truncate(400)}"
      end

      def apply_result!(lead, payload)
        return if payload.blank?

        h = payload.stringify_keys
        match = ActiveModel::Type::Boolean.new.cast(h["match"] || h["matched"])
        reason = (h["reason"] || h["summary"]).to_s.presence

        attrs = {
          ai_match:        match,
          ai_reason:       reason,
          ai_reviewed_at:  Time.current,
          score:           LeadScoring.total_score(lead.raw_post, lead.watcher, ai_match: match)
        }
        attrs[:status] = "ignored" if !match && lead.status == "new"

        lead.update!(attrs)
      end
    end
  end
end
