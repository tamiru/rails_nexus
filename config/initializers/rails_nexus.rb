# frozen_string_literal: true

Rails.application.config.to_prepare do
  RailsNexus.configure do |config|
    # Protect the dashboard - only admin users can access
    config.auth_block = lambda do |controller|
      controller.current_user&.admin?
    end

    # Attach additional data to each exception record
    config.exception_data = lambda do |controller|
      {
        user_id: controller.current_user&.id,
        request_id: controller.request.request_id
      }
    end
  end
end
