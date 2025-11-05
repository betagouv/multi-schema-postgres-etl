require 'dotenv'
Dotenv.load

require_relative "lib/sentry_init"

begin

  require 'optparse'

  APPS = ["rdvi", "rdvsp", "rdvs"].freeze

  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} --app APP"
    opts.on("-a", "--app APP", "Specify the app (rdvi, rdvsp, rdvs)") do |a|
      options[:app] = a
    end
  end.parse!

  app = options[:app]
  raise ArgumentError, "App option is required" if app.nil?

  unless APPS.include?(app)
    raise ArgumentError, "App must be one of: #{APPS.join(', ')}"
  end

  if system("which scalingo")
    puts "⏭️ scalingo-cli already installed…"
  else
    res = system("install-scalingo-cli")
    raise "❌ Failed to install scalingo CLI" unless res
  end

  # scalingo is auto logged in via environment variable SCALINGO_API_TOKEN

  command = %[scalingo --region osc-secnum-fr1 --app rdv-service-public-etl run --detached "bundle exec ruby main.rb --from-cron --app #{app}"]

  puts "Executing command: #{command}…"
  res = system(command)
  raise "❌ Failed to trigger detached run" unless res

  puts "✅ Detached run triggered for app: #{app}"

rescue Exception => e
  Sentry.capture_exception(e)
  raise e
end
