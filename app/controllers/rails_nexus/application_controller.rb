module RailsNexus
  class ApplicationController < ActionController::Base
    include Pagy::Backend

    private

    def rails_nexus_require_auth!
      auth_block = RailsNexus.configuration.auth_block
      return if auth_block.nil?
      return if auth_block.call(self)

      head :forbidden
    end
  end
end
