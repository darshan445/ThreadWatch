class PipelineChannel < ApplicationCable::Channel
  def subscribed
    run_id = params[:run_id]
    return reject unless run_id.present?

    stream_from "pipeline_run_#{run_id}"
  end

  def unsubscribed
    stop_all_streams
  end
end
