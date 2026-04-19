class PipelineRun < ApplicationRecord
  STATUSES     = %w[pending running complete failed].freeze
  TIME_FILTERS = %w[hour day week month year all].freeze

  PRESET_SUBREDDITS = %w[
    entrepreneur freelance smallbusiness SaaS startups
    Accounting projectmanagement marketing sales productivity
  ].freeze

  validates :status,      inclusion: { in: STATUSES }
  validates :time_filter, inclusion: { in: TIME_FILTERS }

  scope :recent,   -> { order(created_at: :desc) }
  scope :running,  -> { where(status: "running") }
  scope :pending,  -> { where(status: "pending") }

  def subreddits_list
    JSON.parse(subreddits || "[]")
  end

  def subreddits_list=(array)
    self.subreddits = array.to_json
  end

  def in_progress?
    status.in?(%w[pending running])
  end

  def elapsed
    return nil unless started_at
    finish = finished_at || Time.current
    (finish - started_at).round(1)
  end

  def append_log(line)
    ts      = Time.current.strftime("%H:%M:%S")
    new_line = "[#{ts}] #{line}\n"
    updated  = "#{log_output}#{new_line}"
    update_column(:log_output, updated)
    broadcast_log(new_line)
  end

  def broadcast_status_update
    ActionCable.server.broadcast("pipeline_run_#{id}", {
      type:       "status",
      status:     status,
      elapsed:    elapsed,
      in_progress: in_progress?
    })
  end

  private

  def broadcast_log(line)
    ActionCable.server.broadcast("pipeline_run_#{id}", {
      type: "log",
      line: line
    })
  end
end
