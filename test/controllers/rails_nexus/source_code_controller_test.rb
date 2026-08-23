# frozen_string_literal: true

require "test_helper"
require "fileutils"

class RailsNexus::SourceCodeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_auth_block = RailsNexus.configuration.auth_block
    RailsNexus.configuration.auth_block = ->(_controller) { true }
    @source_file = Rails.root.join("config/routes.rb")
  end

  teardown do
    RailsNexus.configuration.auth_block = @original_auth_block
  end

  test "reads a valid file inside Rails root" do
    get "/rails_nexus/source_code", params: { file: @source_file.to_s, line: 1, context: 500 }

    assert_response :success
    body = response.parsed_body
    assert_equal @source_file.realpath.to_s, body.dig("source", "file")
    assert_operator body.dig("source", "lines").length, :<=, 51
  end

  test "rejects traversal outside Rails root" do
    get "/rails_nexus/source_code", params: { file: Rails.root.join("..", "Gemfile").to_s, line: 1 }

    assert_response :not_found
  end

  test "rejects a sibling path sharing the Rails root prefix" do
    sibling = "#{Rails.root}-sibling/source.rb"

    get "/rails_nexus/source_code", params: { file: sibling, line: 1 }

    assert_response :not_found
  end

  test "rejects symlinks escaping Rails root" do
    link = Rails.root.join("tmp/rails_nexus-source-link")
    FileUtils.mkdir_p(link.dirname)
    FileUtils.ln_sf("/etc/hosts", link)

    get "/rails_nexus/source_code", params: { file: link.to_s, line: 1 }

    assert_response :not_found
  ensure
    FileUtils.rm_f(link) if link
  end

  test "treats shell characters in a filename as data" do
    file = Rails.root.join("tmp/source;printf-injected.rb")
    FileUtils.mkdir_p(file.dirname)
    File.write(file, "puts :safe\n")

    get "/rails_nexus/source_code", params: { file: file.to_s, line: 1 }

    assert_response :success
    assert_equal "puts :safe", response.parsed_body.dig("source", "lines", 0, "content")
  ensure
    FileUtils.rm_f(file) if file
  end

  test "rejects invalid line numbers" do
    get "/rails_nexus/source_code", params: { file: @source_file.to_s, line: "not-a-line" }

    assert_response :bad_request
  end
end
