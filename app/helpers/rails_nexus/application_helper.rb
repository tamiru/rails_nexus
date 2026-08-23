module RailsNexus
  module ApplicationHelper
    include Pagy::Frontend

    def page_title(text)
      title = [RailsNexus.application_name.presence, text].compact.join(" :: ")
      content_for(:title, title)
    end
  end
end
