import consumer from "@rails/actioncable"

const el = (id) => document.getElementById(id)

function initPipelineChannel() {
  const meta = document.querySelector('meta[name="pipeline-run-id"]')
  if (!meta) return

  const runId = meta.content

  consumer.subscriptions.create(
    { channel: "PipelineChannel", run_id: runId },
    {
      received(data) {
        if (data.type === "log")    handleLog(data)
        if (data.type === "status") handleStatus(data)
      }
    }
  )
}

function handleLog(data) {
  const log = el("log-body")
  if (!log) return
  log.textContent += data.line
  log.scrollTop = log.scrollHeight
}

function handleStatus(data) {
  const badge = el("status-badge")
  if (badge) {
    badge.className = `status-badge status-${data.status}`
    badge.innerHTML = data.status === "running"
      ? `<span class="run-pulse"></span> ${data.status}`
      : data.status
  }

  const liveIndicator = el("log-live")
  if (liveIndicator) {
    liveIndicator.style.display = data.in_progress ? "" : "none"
  }

  const elapsed = el("elapsed")
  if (elapsed && data.elapsed) elapsed.textContent = `${data.elapsed}s elapsed`

  if (data.status === "complete") {
    const resultLinks = el("result-links")
    if (resultLinks) resultLinks.style.display = ""
    updateNavButton(false)
  } else if (data.status === "failed") {
    updateNavButton(false)
  } else if (data.status === "running") {
    updateNavButton(true)
  }
}

function updateNavButton(running) {
  const btn = el("nav-run-btn")
  if (!btn) return
  if (running) {
    btn.classList.add("nav-run-btn--active")
    btn.innerHTML = '<span class="run-pulse"></span> Running…'
  } else {
    btn.classList.remove("nav-run-btn--active")
    btn.innerHTML = "▶ Run Pipeline"
  }
}

document.addEventListener("DOMContentLoaded", initPipelineChannel)
