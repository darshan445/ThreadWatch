# frozen_string_literal: true

require "cgi"

module Scrapers
  # All HTTP communication with the Reddit public JSON API.
  # Rotates through a proxy pool on every request to avoid rate limits.
  # Tracks burned subreddits (persistent 429) and dead proxies (403) per run.
  class RedditApiClient
    BASE_URL          = "https://www.reddit.com"
    MAX_COMMENT_DEPTH = 3
    HEADERS           = { "User-Agent" => "thread-watch/1.0 by FrequentBike8327" }.freeze

    PROXIES = [
      { host: "31.59.20.176",   port: 6754, user: "ypkjuetb", pass: "ceqkd3fts49t" },
      { host: "198.23.239.134", port: 6540, user: "ypkjuetb", pass: "ceqkd3fts49t" },
      { host: "31.56.127.193",  port: 7684, user: "ypkjuetb", pass: "ceqkd3fts49t" },
      { host: "45.38.107.97",   port: 6014, user: "ypkjuetb", pass: "ceqkd3fts49t" },
      { host: "107.172.163.27", port: 6543, user: "ypkjuetb", pass: "ceqkd3fts49t" },
      { host: "216.10.27.159",  port: 6837, user: "ypkjuetb", pass: "ceqkd3fts49t" },
      { host: "142.111.67.146", port: 5611, user: "ypkjuetb", pass: "ceqkd3fts49t" },
      { host: "191.96.254.138", port: 6185, user: "ypkjuetb", pass: "ceqkd3fts49t" },
      { host: "31.58.9.4",      port: 6077, user: "ypkjuetb", pass: "ceqkd3fts49t" },
      { host: "23.229.19.94",   port: 8689, user: "ypkjuetb", pass: "ceqkd3fts49t" }
    ].freeze

    def initialize
      @proxy_counter     = 0
      @dead_proxies      = Set.new
      @burned_subreddits = Set.new
    end

    def subreddit_burned?(subreddit)
      @burned_subreddits.include?(subreddit)
    end

    # Returns array of raw post data hashes from Reddit search.
    def search_posts(subreddit, query, sort: "new", time_filter: "day", limit: 25)
      url      = "#{BASE_URL}/r/#{CGI.escape(subreddit)}/search.json"
      response = get(url, query: {
        q:           query,
        sort:        sort,
        t:           time_filter,
        limit:       limit,
        restrict_sr: "true"
      })

      return [] unless response.success?

      (response.dig("data", "children") || [])
        .select { |c| c["kind"] == "t3" }
        .map    { |c| c["data"] }
    end

    # Returns flat array of comment tree nodes for a post permalink.
    def fetch_comment_nodes(permalink)
      return [] if permalink.blank?

      path     = permalink.start_with?("/") ? permalink : "/#{permalink}"
      url      = "#{BASE_URL}#{path}.json"
      response = get(url, query: { limit: 50, depth: MAX_COMMENT_DEPTH, sort: "top" })

      return [] unless response.success?

      parsed = response.parsed_response
      parsed = JSON.parse(response.body) if parsed.is_a?(String)
      return [] unless parsed.is_a?(Array) && parsed.size >= 2

      parsed.dig(1, "data", "children") || []
    rescue => e
      Rails.logger.warn "[RedditApiClient] comment_fetch_error permalink=#{permalink} #{e.class}: #{e.message}"
      []
    end

    private

    def get(url, query: {})
      proxy, proxy_idx = next_proxy
      Rails.logger.info "[RedditApiClient] GET #{url} via #{proxy[:host]}:#{proxy[:port]}"

      response = HTTParty.get(url, query: query, headers: HEADERS, timeout: 30,
                                   **proxy_options(proxy))

      # 429 — rotate to a fresh IP and retry once
      if response.code == 429
        Rails.logger.warn "[RedditApiClient] 429 via #{proxy[:host]} — rotating proxy"
        proxy, proxy_idx = next_proxy
        response = HTTParty.get(url, query: query, headers: HEADERS, timeout: 30,
                                     **proxy_options(proxy))
      end

      # Still 429 after retry — burn the subreddit for this run
      burn_subreddit_from(url) if response.code == 429

      # 403 — Reddit has blocked this proxy IP
      if response.code == 403
        Rails.logger.warn "[RedditApiClient] 403 via #{proxy[:host]} — marking proxy dead"
        @dead_proxies << proxy_idx
      end

      response
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
      Rails.logger.warn "[RedditApiClient] network_error via #{proxy&.dig(:host)}: #{e.class} #{e.message}"
      @dead_proxies << proxy_idx if proxy_idx
      raise
    end

    def next_proxy
      live = (0...PROXIES.size).reject { |i| @dead_proxies.include?(i) }
      if live.empty?
        Rails.logger.warn "[RedditApiClient] all proxies dead — resetting dead-list"
        @dead_proxies.clear
        live = (0...PROXIES.size).to_a
      end
      idx = live[@proxy_counter % live.size]
      @proxy_counter += 1
      [PROXIES[idx], idx]
    end

    def proxy_options(proxy)
      {
        http_proxyaddr: proxy[:host],
        http_proxyport: proxy[:port],
        http_proxyuser: proxy[:user],
        http_proxypass: proxy[:pass]
      }
    end

    def burn_subreddit_from(url)
      return unless (m = url.match(%r{/r/([^/?.]+)}))

      @burned_subreddits << m[1]
      Rails.logger.warn "[RedditApiClient] subreddit_burned r/#{m[1]} — skipping for this run"
    end
  end
end
