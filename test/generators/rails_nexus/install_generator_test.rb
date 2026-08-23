# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/rails_nexus/install_generator"

class RailsNexus::Generators::InstallGeneratorTest < Rails::Generators::TestCase
  tests RailsNexus::Generators::InstallGenerator
  destination Rails.root.join("tmp/generators")

  setup do
    prepare_destination

    FileUtils.mkdir_p File.join(destination_root, "config")
    File.write File.join(destination_root, "config/routes.rb"), <<~RUBY
      Rails.application.routes.draw do
      end
    RUBY

    FileUtils.mkdir_p File.join(destination_root, "app/controllers")
    File.write File.join(destination_root, "app/controllers/application_controller.rb"), <<~RUBY
      class ApplicationController < ActionController::Base
      end
    RUBY
  end

  test "generates the complete RailsNexus installation" do
    run_generator

    %w[
      create_rails_nexus_exceptions
      add_advanced_features_to_rails_nexus_exceptions
      add_platform_to_rails_nexus_exceptions
      add_workflow_to_rails_nexus
      create_rails_nexus_cron_jobs
      create_rails_nexus_webhook_deliveries
      create_rails_nexus_metrics_tables
    ].each do |migration|
      assert_migration "db/migrate/#{migration}.rb"
    end

    assert_file "config/initializers/rails_nexus.rb" do |content|
      assert_match(/RailsNexus\.configure/, content)
    end

    assert_file "config/routes.rb" do |content|
      assert_match(%r{mount RailsNexus::Engine, at: "/rails_nexus"}, content)
    end

    assert_file "app/controllers/application_controller.rb" do |content|
      assert_match(/rescue_from Exception, with: :log_exception_handler/, content)
    end
  end
end
