module RailsNexus
  class ApplicationController < ActionController::Base
    include Pagy::Method
    protect_from_forgery with: :exception
    before_action :rails_nexus_require_auth!

    private

    def rails_nexus_pagy(collection, **options)
      limit = options.delete(:limit) || RailsNexus.configuration.per_page || 30
      pagy(:offset, collection, limit: limit, **options)
    end

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
