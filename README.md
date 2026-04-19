# ThreadWatch

A Rails SaaS app that scrapes Reddit for pain-point posts and comments,
stores them in PostgreSQL, and surfaces them via a web dashboard.

Built on top of the scraping infrastructure from problem-miner.

---

## Stack

- **Rails 7.1** — web framework
- **PostgreSQL** — primary database
- **Sidekiq + Redis** — background job processing
- **Action Cable** — real-time log streaming during scrape runs

---

## How it works

```
Dashboard → Start Scrape Run
       │
       ▼ (ScrapeJob via Sidekiq)
Reddit Search API
       │
       ▼
RawPost  (title, body, url, upvotes, metadata)
       │
       ▼ (posts with >5 comments)
PostComment  (body, score, depth 0–1)
```

---

## Setup

### 1. Install dependencies

```bash
bundle install
```

### 2. Start services

```bash
redis-server
```

### 3. Database

```bash
rails db:create db:migrate
```

### 4. Start the app

```bash
# Terminal 1 — Rails server
rails server

# Terminal 2 — Sidekiq worker
bundle exec sidekiq -C config/sidekiq.yml
```

Visit **http://localhost:3000** → click **Scrape Reddit** to kick off a run.

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USERNAME` | `postgres` | PostgreSQL user |
| `DB_PASSWORD` | _(empty)_ | PostgreSQL password |
| `DB_NAME` | `thread_watch_production` | Production DB name |
| `REDIS_URL` | `redis://localhost:6379/0` | Redis connection URL |
| `RAILS_MASTER_KEY` | — | Decrypts credentials |

---

## Rake tasks

```bash
# Scrape subreddits directly from the CLI
rails scrape:reddit SUBREDDITS=entrepreneur,SaaS LIMIT=50
```
