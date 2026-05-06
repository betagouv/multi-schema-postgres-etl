require "minitest/autorun"
require_relative "../lib/etl"

class TestEtl < Minitest::Test
  ETL_DB_URL = "postgresql://localhost/rdv_sp_etl_test_target"
  CONFIG_PATH = File.expand_path("config.yml", File.dirname(__FILE__))
  SEEDS_DUMP_PATH = File.expand_path("seeds_dump.pgsql", File.dirname(__FILE__))

  def teardown
    ActiveRecord::Base.connection_handler.clear_all_connections!
  end

  def setup
    system "dropdb --if-exists rdv_sp_etl_test_source"
    system "dropdb --if-exists rdv_sp_etl_test_target"
    system "dropuser --if-exists rdv_sp_etl_metabase_user"
    system "dropuser --if-exists rdvs_schema_reader_user"

    system "createdb rdv_sp_etl_test_source"
    # pg_dump --format tar --clean --no-privileges postgresql://localhost/lapin_development -f ../rdv-service-public-etl/tests/seeds_dump.pgsql
    system "pg_restore --no-owner -d postgresql://localhost/rdv_sp_etl_test_source #{SEEDS_DUMP_PATH}"
    system "createdb rdv_sp_etl_test_target"
    system %Q(echo "CREATE ROLE rdv_sp_etl_metabase_user WITH LOGIN PASSWORD 'metabase_password'" | psql -d rdv_sp_etl_test_target;)
    system %Q(echo "CREATE ROLE rdvs_schema_reader_user WITH LOGIN PASSWORD 'reader_password'" | psql -d rdv_sp_etl_test_target;)
  end

  def test_something
    Etl.new(
      app: "rdvs",
      etl_db_url: ETL_DB_URL,
      origin_db_url: "postgresql://localhost/rdv_sp_etl_test_source",
      config_path: CONFIG_PATH,
      metabase_username: "rdv_sp_etl_metabase_user"
    ).run

    ActiveRecord::Base.establish_connection "postgresql://rdv_sp_etl_metabase_user:metabase_password@localhost/rdv_sp_etl_test_target"
    users_rows = ActiveRecord::Base.connection.execute(
      Arel::Table.new("rdvs.users").project(:id, :first_name, :created_through).to_sql
    )
    assert_equal users_rows[0]["first_name"], "[valeur unique anonymisée #{users_rows[0]["id"]}]"
    assert_equal users_rows[1]["first_name"], "[valeur unique anonymisée #{users_rows[1]["id"]}]"
    assert_equal users_rows[0]["created_through"], "user_sign_up" # colonne ENUM
  end

  def test_schema_reader_has_access_when_declared
    Etl.new(
      app: "rdvs",
      etl_db_url: ETL_DB_URL,
      origin_db_url: "postgresql://localhost/rdv_sp_etl_test_source",
      config_path: CONFIG_PATH,
      metabase_username: "rdv_sp_etl_metabase_user",
      schema_reader_username: "rdvs_schema_reader_user"
    ).run

    ActiveRecord::Base.establish_connection "postgresql://rdvs_schema_reader_user:reader_password@localhost/rdv_sp_etl_test_target"
    users_rows = ActiveRecord::Base.connection.execute(
      Arel::Table.new("rdvs.users").project(:id).to_sql
    )
    assert users_rows.count > 0
  end
end
