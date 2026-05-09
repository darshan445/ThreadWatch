# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Wrapper around the Gemini REST API using Net::HTTP (no extra gem needed).
# Reads the API key from credentials[:gemini][:api_key] or ENV["GEMINI_API_KEY"].
class GeminiClient
  GEMINI_HOST  = "generativelanguage.googleapis.com"
  GEMINI_MODEL = "gemini-2.5-flash"
  GEMINI_PATH  = "/v1beta/models/#{GEMINI_MODEL}:generateContent"

  class << self
    def api_key
      Rails.application.credentials.dig(:gemini, :api_key).presence ||
        ENV["GEMINI_API_KEY"].presence
    end

    def api_key?
      api_key.present?
    end

    # Call Gemini and return the text of the first candidate.
    # Raises on non-2xx, empty response, or truncated output.
    def generate(system:, user:, max_tokens: 512, temperature: 0.3)
      raise "Gemini API key not configured" if api_key.blank?

      uri = URI::HTTPS.build(
        host:  GEMINI_HOST,
        path:  GEMINI_PATH,
        query: URI.encode_www_form({ key: api_key })
      )

      body = {
        "system_instruction" => { "parts" => [{ "text" => system }] },
        "contents"           => [{ "parts" => [{ "text" => user }] }],
        "generationConfig"   => {
          "temperature"     => temperature,
          "maxOutputTokens" => max_tokens,
          "thinkingConfig"  => { "thinkingBudget" => 0 }
        }
      }

      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 30
      http.open_timeout = 10

      request                 = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request.body            = JSON.generate(body)

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise "Gemini API error #{response.code}: #{response.body.to_s.truncate(300)}"
      end

      parsed    = JSON.parse(response.body)
      candidate = parsed.dig("candidates", 0)
      raise "Gemini returned empty response" if candidate.blank?
      raise "Gemini output truncated (token limit)" if candidate["finishReason"].to_s == "MAX_TOKENS"

      text = candidate.dig("content", "parts", 0, "text").to_s.strip
      raise "Gemini returned empty content" if text.blank?

      text
    end
  end
end
