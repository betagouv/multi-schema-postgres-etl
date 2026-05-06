require "active_support/all"
require 'anonymizer'
require 'yaml'
require "fileutils"

require_relative 'utils'

class Etl
  include Utils

  attr_reader :app, :etl_db_url, :origin_db_url, :config_path, :metabase_username, :schema_reader_username

  def initialize(app:, etl_db_url:, origin_db_url:, config_path:, metabase_username:, schema_reader_username: nil)
    @app = app

    @etl_db_url = etl_db_url
    @origin_db_url = origin_db_url
    @config_path = config_path
    @metabase_username = metabase_username
    @schema_reader_username = schema_reader_username
  end

  def run
    # only useful on Scalingo apps
    run_command "dbclient-fetcher pgsql 16" if find_executable('dbclient-fetcher')

    # STEP : load anonymizer config
    @config = Anonymizer::Config.new(YAML.safe_load(File.read(config_path)))

    # make sure RDV db connection works
    log_around "connect to origin database #{origin_db_url}" do
      ActiveRecord::Base.establish_connection origin_db_url
      ActiveRecord::Base.connection # triggers connection
    end

    log_around "validate config exhaustivity" do
      Anonymizer.validate_exhaustivity!(config: @config)
    end

    ActiveRecord::Base.connection_handler.clear_all_connections!

    # make sure ETL db connection works to avoid useless dumps
    log_around "connect to ETL database #{etl_db_url}" do
      ActiveRecord::Base.establish_connection etl_db_url
      ActiveRecord::Base.connection # triggers connection
    end

    # STEP : dump from distant RDVSP or RDVI database
    unless ENV['CACHE_DUMP'] && File.exist?(dump_filename)
      run_command(
        <<~SH.strip_heredoc
          pg_dump --clean --no-privileges --format tar \
            #{@config.truncated_table_names.map { "--exclude-table #{_1}" }.join(' ')} \
            -f #{dump_filename} \
            #{origin_db_url}
        SH
      )
    end

    # STEP : restore dump to ETL database, without indexes, in public schema
    # cf https://www.postgresql.org/docs/current/app-pgrestore.html
    # The data section contains actual table data as well as large-object definitions.
    # Post-data items consist of definitions of indexes, triggers, rules and constraints other than validated check constraints.
    # Pre-data items consist of all other data definition items.
    run_sql_script 'clean_public_schema.sql'
    run_command %(pg_restore --clean --if-exists --no-owner --section=pre-data --section=data -d #{etl_db_url} #{dump_filename})

    # STEP : anonymize and truncate all tables
    log_around('Anonymizing database') do
      @config.table_configs.each do |table_config|
        next unless ActiveRecord::Base.connection.table_exists?(table_config.table_name)
        Anonymizer::Table.new(table_config:).anonymize_records!
      end
    end

    # STEP : restore indexes
    run_command %(pg_restore --clean --if-exists --no-owner --section=post-data -d #{etl_db_url} #{dump_filename})

    # delete the dump file as soon as possible
    FileUtils.rm(dump_filename) unless ENV['CACHE_DUMP']

    # workaround for a problematic column that we could also exclude
    # ERROR:  cannot insert a non-DEFAULT value into column "text_search_terms" (PG::GeneratedAlways)
    # DÉTAIL : Column "text_search_terms" and "text_search_terms_with_notification_email" are generated columns.
    # Vérifier que la table users existe avant de faire l'alter table
    if ActiveRecord::Base.connection.table_exists?("users")
      run_sql_command %(ALTER TABLE users DROP COLUMN IF EXISTS text_search_terms CASCADE)
      run_sql_command %(ALTER TABLE users DROP COLUMN IF EXISTS text_search_terms_with_notification_email CASCADE)
    else
      logger.info "La table users n'existe pas, aucune modification n'est appliquée."
    end

    # STEP : move from public to target schema
    target_schema = app
    run_sql_command %(DROP SCHEMA IF EXISTS #{target_schema} CASCADE;)
    run_sql_script 'clone_schema.sql' # loads the clone_schema function without calling it
    run_sql_command %(SELECT clone_schema('public', '#{target_schema}', TRUE);)
    run_sql_command %(GRANT USAGE ON SCHEMA #{target_schema} TO #{metabase_username};)
    run_sql_command %(GRANT SELECT ON ALL TABLES IN SCHEMA #{target_schema} TO #{metabase_username};)
    if schema_reader_username
      run_sql_command %(GRANT USAGE ON SCHEMA #{target_schema} TO #{schema_reader_username};)
      run_sql_command %(GRANT SELECT ON ALL TABLES IN SCHEMA #{target_schema} TO #{schema_reader_username};)
    end
    run_sql_script 'clean_public_schema.sql'
  ensure
    ActiveRecord::Base.connection_handler.clear_all_connections!
  end

  def dump_filename
    @dump_filename ||= "dump.#{app}.#{Time.now.strftime('%Y-%m-%d')}.pgsql.tar"
  end
end
