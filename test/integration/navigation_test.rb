require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  test "engine importmap is composed into the host application" do
    packages = Rails.application.importmap.packages

    assert_equal "rails_nexus/application.js", packages.fetch("rails_nexus/application").path
    assert_equal "turbo.min.js", packages.fetch("@hotwired/turbo-rails").path
    assert_equal "stimulus.min.js", packages.fetch("@hotwired/stimulus").path
  end

  test "all engine importmap assets resolve through the host asset pipeline" do
    imports = JSON.parse(
      Rails.application.importmap.to_json(resolver: ActionController::Base.helpers)
    ).fetch("imports")

    assert_match %r{/assets/rails_nexus/application-.*\.js}, imports.fetch("rails_nexus/application")
    assert_match %r{/assets/controllers/rails_nexus_controller-.*\.js}, imports.fetch("rails_nexus/controllers/rails_nexus")
    assert_match %r{/assets/turbo\.min-.*\.js}, imports.fetch("@hotwired/turbo-rails")
    assert_match %r{/assets/stimulus\.min-.*\.js}, imports.fetch("@hotwired/stimulus")
  end
end
