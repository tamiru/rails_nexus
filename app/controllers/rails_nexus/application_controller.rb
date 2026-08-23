module RailsNexus
  class ApplicationController < ActionController::Base
    include Pagy::Backend
    protect_from_forgery with: :exception
    before_action :rails_nexus_require_auth!

    private

    def rails_nexus_require_auth!
      auth_block = RailsNexus.configuration.auth_block
      return if auth_block&.call(self)

      head :forbidden
    rescue StandardError => error
      Rails.logger.error("[RailsNexus] Authentication error: #{error.class}: #{error.message}")
      head :forbidden
    end
  end
end
