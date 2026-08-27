module RailsNexus
  module ApplicationHelper
    def page_title(text)
      title = [RailsNexus.application_name.presence, text].compact.join(" :: ")
      content_for(:title, title)
    end

    def rails_nexus_pagy_nav(pagy)
      pagy.series_nav
    end
  end
end
