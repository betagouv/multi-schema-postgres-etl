require 'dotenv'
Dotenv.load

require_relative "lib/sentry_init"

begin

  require "active_support/all"
  require 'optparse'

  require_relative "lib/etl"
  require_relative "lib/utils"

  include Utils

  config_url = {
    "rdvi" => "https://raw.githubusercontent.com/betagouv/rdv-insertion/main/config/anonymizer.yml",
    "rdvs" => "https://raw.githubusercontent.com/betagouv/rdv-service-public/production/config/anonymizer.yml",
    "rdvsp" => "https://raw.githubusercontent.com/betagouv/rdv-service-public/production/config/anonymizer.yml"
  }

  rdv_db_url_list = {
    "rdvi" => "RDV_INSERTION_DB_URL",
    "rdvs" => "RDV_SOLIDARITES_DB_URL",
    "rdvsp" => "RDV_SERVICE_PUBLIC_DB_URL"
  }

  # unlike metabase_username which has access to all schemas, each schema reader is a db user that
  # only has access to its own schema
  schema_reader_username_list = {
    "rdvi" => "RDV_INSERTION_SCHEMA_READER_USERNAME",
    "rdvs" => "RDV_SOLIDARITES_SCHEMA_READER_USERNAME",
    "rdvsp" => "RDV_SERVICE_PUBLIC_SCHEMA_READER_USERNAME"
  }

  app = ENV["APP"]
  from_cron = false
  dry_run = false
  OptionParser.new do |opts|
    opts.on('-a', '--app APP', config_url.keys) { app = _1 }
    opts.on('-c', '--from-cron', "Monitor run if it comes from a CRON schedule") { from_cron = true }
    opts.on('-d', '--dry-run', "Skip actually running the ETL") { dry_run = true }
  end.parse!

  if app.nil?
    raise "Définissez une variable d'environnement APP ou passez un argument --app"
  end

  sentry_monitor_helper = get_sentry_monitor_helpers[app] if from_cron
  sentry_monitor_helper.capture_start if from_cron

  if config_url.key?(app)
    config_path = config_url[app]
    origin_db_url_env_var = rdv_db_url_list[app]
  else
    unless ENV["CONFIG_PATH"]
      raise "La variable d'environnement CONFIG_PATH n'est pas définie"
    end


    config_path = ENV["CONFIG_PATH"]

    origin_db_url_env_var = "ORIGIN_DB_URL"
  end

  # Si le nom du fichier commence par https://, alors il s'agit d'une URL
  if config_path.starts_with?("https://")
    # Télécharger le fichier
    run_command "curl -o config.yml \"#{config_path}\""
    config_path = "config.yml"
  end

  unless File.exist?(config_path)
    raise "La variable d'environnement CONFIG_PATH pointe vers un fichier inexistant"
  end


  etl_db_url_env_var = "ETL_DB_URL"
  metabase_username_env_var = "METABASE_USERNAME"

  [
    origin_db_url_env_var,
    etl_db_url_env_var,
    metabase_username_env_var
  ].each do |env_var|
    raise "Missing environment variable #{env_var}" if ENV[env_var].blank?
  end

  origin_db_url = ENV[origin_db_url_env_var]
  etl_db_url = ENV[etl_db_url_env_var]
  metabase_username = ENV[metabase_username_env_var]
  schema_reader_username = ENV[schema_reader_username_list[app]] if schema_reader_username_list.key?(app)

  if dry_run
    puts "pretend working…"
    sleep 2
  else
    Etl.new(app:, etl_db_url:, origin_db_url:, config_path:, metabase_username:, schema_reader_username:).run
  end

  sentry_monitor_helper.capture_end_successful if from_cron

rescue Exception => e
  sentry_monitor_helper.capture_error if from_cron && sentry_monitor_helper
  Sentry.capture_exception(e)
  raise e
end
