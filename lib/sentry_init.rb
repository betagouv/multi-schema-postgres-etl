require 'sentry-ruby'

if ENV["SENTRY_DSN"]
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
  end
end

def get_sentry_monitor_helpers
  crontab = JSON.parse(File.read(File.join(File.dirname(__FILE__), '../cron.json')))
  %w[rdvsp rdvs rdvi].to_h do |app|
    cron_item = crontab["jobs"].find { _1["command"].include?("--app #{app}") }
    cron_exp = cron_item["command"].split("bundle")[0]
    [app, SentryMonitorHelper.new(app:, cron_exp:)]
  end
end

class SentryMonitorHelper
  attr_reader :check_in_id

  def initialize(app:, cron_exp:)
    @app = app
    @cron_exp = cron_exp
  end

  def slug = "etl-production-#{@app}"

  def monitor_config
    @config ||= Sentry::Cron::MonitorConfig.from_crontab(
      @cron_exp,
      checkin_margin: 10,
      max_runtime: @app == "rdvs" ? 110 : 50,
      timezone: "UTC"
    )
  end

  def capture_start
    @check_in_id = Sentry.capture_check_in(slug, :in_progress, monitor_config:)
  end

  def capture_end_successful
    Sentry.capture_check_in(slug, :ok, monitor_config:, check_in_id:)
  end

  def capture_error
    Sentry.capture_check_in(slug, :error, monitor_config:, check_in_id:)
  end
end

