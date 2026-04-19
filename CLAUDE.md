# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Reddit-Leads is a Rails 7.1 SaaS MVP that scrapes Reddit for pain-point posts/comments, stores them in PostgreSQL, and surfaces them via a web dashboard. Users configure **Watchers** (keyword + subreddit combos), which background jobs process every 30 minutes to generate scored **Leads**.

## Stack

- **Runtime:** Ruby 3.0.0, Rails 7.1.6
- **Database:** PostgreSQL (via `pg`)
- **Background Jobs:** Sidekiq 7 + Redis + sidekiq-cron (scheduled jobs)
- **Auth:** Devise (custom path names: login/logout/register)
- **Email:** ActionMailer (SMTP in production via `SMTP_*` env vars)
- **HTTP scraping:** HTTParty
- **Real-time:** ActionCable (WebSockets)
- **JS:** Importmap (ESM, no Node/bundler needed), Turbo Rails (Turbo Streams)

## Common Commands

```bash
# Setup
bundle install
rails db:create db:migrate

# Run (need both processes)
rails server
sidekiq

# Rake-based scraping (CLI alternative to UI)
rails scrape:reddit WATCHER_ID=1
rails scrape:reddit SUBREDDITS=entrepreneur,freelance KEYWORDS="I wish" LIMIT=100

# Database
rails db:migrate
rails db:rollback
rails console
```

Local PostgreSQL defaults: user `postgres`, password `postgres`, host `localhost`.
Redis defaults to `redis://localhost:6379`.

## Architecture

### Data Flow

**Ad-hoc (dashboard-triggered):**
1. User triggers a scrape from the UI → creates a **PipelineRun**
2. `ScrapeJob` runs `Scrapers::RedditScraper` with a `PipelineRun`'s subreddits/keywords
3. Live log output streamed to browser via ActionCable (`PipelineChannel`)

**Automated (background):**
1. sidekiq-cron fires `ScheduleWatchersJob` every 30 minutes
2. It enqueues a `WatcherCheckJob` per active Watcher
3. `WatcherCheckJob` calls `Scrapers::RedditScraper.call(watcher:)` if user has `active_account?`
4. Results stored as **RawPost** + **PostComment** records
5. **Lead** records created per Watcher with a computed score

**Daily digest:**
- sidekiq-cron fires `DailyDigestJob` at 8am → sends `DigestMailer#daily_digest` to all active users

### Key Model Notes

- **Watcher** — DB table `watchers` (renamed from `monitors` in migration `20260419000001`). Keywords and subreddits stored as CSV strings, parsed via `keywords_list` / `subreddits_list`.
- **Lead** — FK `watcher_id`. Statuses: `new → saved → replied → converted / ignored`. Scopes: `fresh`, `actionable`, `by_status`, `by_score`.
- **RawPost** — unique index on `(source, external_id)` to deduplicate across scrape runs. `processed` boolean guards duplicate Lead creation.
- **PipelineRun** — for ad-hoc dashboard-triggered scrapes with live logging; separate from Watcher-based scraping.
- **ReplyTemplate** — belongs to User; `use_count` incremented via `PATCH /dashboard/reply_templates/:id/use` (background fetch from the lead card templates dropdown).

### Scoring (in `RedditScraper`)

`score = min(upvotes, 100) + min(comment_count × 2, 50) + recency_bonus`
Recency bonus: 50 (< 2h), 30 (< 6h), 10 (< 24h), 0 otherwise.

### ActionCable

`PipelineChannel` subscribes to `pipeline_run_{id}` stream. `PipelineRun#append_log` and `#broadcast_status_update` push to this stream during scrape execution.

### Controllers

All dashboard routes live under `Dashboard::` namespace and inherit from `Dashboard::BaseController`, which enforces `authenticate_user!` and `require_active_account!`.

`LandingController#index` redirects to the dashboard only for users with `active_account?` (signed-in users with expired trials stay on the landing/pricing page to avoid a redirect loop).

### Auth / Access

- Devise with custom path names: `login`, `logout`, `register`
- `before_create` callback sets `trial_ends_at = 7.days.from_now` on sign-up
- `trial_active?` — true if `trial_ends_at` is in the future (alias: `on_trial?`)
- `active_account?` — true if `trial_active?` OR `subscribed?` (alias: `active_access?`)
- `require_active_account!` in `ApplicationController` redirects expired users to `/pricing`

### Turbo Streams

Lead status updates (`PATCH /dashboard/leads/:id`) respond with `format.turbo_stream`, replacing the `lead_<id>` DOM element in-place using the `dashboard/leads/_lead_card` partial. No full-page reload needed.

### Background Jobs

| Job | Trigger | Purpose |
|-----|---------|---------|
| `WatcherCheckJob` | enqueued by `ScheduleWatchersJob` | Scrapes Reddit for one Watcher |
| `ScheduleWatchersJob` | sidekiq-cron every 30 min | Fans out `WatcherCheckJob` per active Watcher |
| `DailyDigestJob` | sidekiq-cron 8am daily | Sends digest email to all active users |
| `ScrapeJob` | dashboard UI (PipelineRun) | Ad-hoc scrape with live log streaming |

### Email

`DigestMailer#daily_digest(user)` — queries last-24h `new` leads, groups by watcher, sorts by score DESC, caps at 10 per watcher. Skips sending if zero leads. Both HTML and plain-text templates exist.

Production SMTP configured via env vars: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `APP_HOST`, `MAILER_FROM`.

### Routes Summary

```
GET  /                          → landing#index
GET  /pricing                   → landing#index (anchors to #pricing)

namespace :dashboard do
  root                          → home#index
  resources :watchers           → full CRUD; show = lead feed for that watcher
  resources :leads              → index, show, update (Turbo Stream)
  resources :reply_templates    → full CRUD + PATCH :use (increment use_count)
end
```

### No Test Suite

There are no test files (`spec/` or `test/`). System tests are disabled in `config/application.rb`.
