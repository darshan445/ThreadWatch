# frozen_string_literal: true

class AnalyzeLeadRelevanceBatchJob < ApplicationJob
  queue_as :default

  # +lead_ids+ — one id or an array (e.g. batched after a scrape run).
  def perform(lead_ids)
    ids = Array(lead_ids).flatten.map(&:to_i).uniq
    return if ids.empty?

    Analyzers::LeadRelevanceAnalyzer.analyze_lead_ids!(ids)
  rescue StandardError => e
    Rails.logger.error "[AnalyzeLeadRelevanceBatchJob] #{e.class}: #{e.message}"
    raise
  end
end
