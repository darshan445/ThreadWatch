# frozen_string_literal: true

module Analyzers
  # Builds Anthropic prompts: generic system message; product/ICP context only in the user message.
  class LeadQualifier
    SYSTEM_PROMPT = <<~TXT.squish
      You classify Reddit threads against the business context provided in the user message.
      Decide if the thread shows real need or buying intent aligned with that context (not mere keyword overlap).
      Output JSON only, no markdown. If unsure, use match:false.
      Single lead: {"match":bool,"reason":"<12 words>"}
      Batch: {"results":[{"lead_id":int,"match":bool,"reason":"<12 words>"},...]}
    TXT

    class << self
      def watcher_context(watcher)
        desc = watcher.description.to_s.strip
        product_line = if desc.present?
                         desc
                       else
                         "(Not specified — infer fit from watcher name and keywords only.)"
                       end

        <<~TXT.strip
          Watcher name: #{watcher.name}
          Search keywords: #{watcher.keywords}
          Product / ideal buyer: #{product_line}
        TXT
      end

      # Full user message for one lead (thread text from LeadRelevanceAnalyzer#compact_thread).
      def build_prompt(lead, thread_text:)
        [
          watcher_context(lead.watcher),
          "Reddit thread:",
          thread_text.to_s.strip,
          "Reply: single JSON object only."
        ].join("\n\n")
      end

      # Batch: one block per lead with its own watcher context + compact thread.
      def build_batch_prompt(leads, thread_text_for:)
        blocks = leads.map do |lead|
          th = thread_text_for.call(lead)
          <<~BLK.strip
            L#{lead.id}
            #{watcher_context(lead.watcher)}
            Reddit thread: #{th}
          BLK
        end

        [
          "Batch JSON with results for lead_ids: #{leads.map(&:id).join(",")}",
          blocks.join("\n\n---\n\n")
        ].join("\n\n")
      end
    end
  end
end
