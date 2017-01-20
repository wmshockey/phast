json.array!(@schedules) do |schedule|
  json.extract! schedule, :id, :name, :description, :start_date, :period, :pipeline_id, :sched_type
  json.url schedule_url(schedule, format: :json)
end
