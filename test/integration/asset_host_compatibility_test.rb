# frozen_string_literal: true

require "test_helper"

class AssetHostCompatibilityTest < ActiveSupport::TestCase
  setup do
    @gemspec = Gem::Specification.load(RailsNexus::Engine.root.join("rails_nexus.gemspec").to_s)
    @source = RailsNexus::Engine.root.join("app/javascript/rails_nexus/application.js").read
    @bundle = RailsNexus::Engine.root.join("app/assets/javascripts/rails_nexus/application.js").read
  end

  test "Importmap hosts are not forced to install or compose importmap-rails" do
    refute_includes @gemspec.runtime_dependencies.map(&:name), "importmap-rails"
    refute(RailsNexus::Engine.initializers.any? { |initializer| initializer.name == "rails_nexus.importmap" })
  end

  test "jsbundling hosts do not need to import the engine entry point" do
    layout = RailsNexus::Engine.root.join("app/views/layouts/rails_nexus/application.html.erb").read

    assert_includes layout, 'javascript_include_tag "rails_nexus/application"'
    refute_includes layout, "javascript_importmap_tags"
  end

  test "prebuilt bundle supplies namespaced controllers when no host bundler exists" do
    assert_includes @bundle, "rails_nexus-detail"
    assert_includes @bundle, "rails_nexus-sidebar"
    assert_operator @bundle.bytesize, :>, 100_000
  end

  test "bundle reuses exposed host runtimes and its own singleton" do
    assert_includes @source, "if (window.Turbo) return"
    assert_includes @source, "window.Stimulus?.register"
    assert_includes @source, "window.RailsNexusStimulus ||="
  end
end
