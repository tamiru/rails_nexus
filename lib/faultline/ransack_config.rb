# frozen_string_literal: true

# Configure Ransack for Faultline LoggedException model.
# Ransack 4.x automatically adds `.ransack` to ActiveRecord::Relation via its railtie.
# We just need to declare which attributes are searchable.
module Faultline
  module RansackConfig
    def self.apply!
      return unless defined?(Ransack)

      Faultline::LoggedException.class_eval do
        def self.ransackable_attributes(auth_object = nil)
          %w[exception_class controller_name action_name message created_at]
        end

        def self.ransackable_associations(auth_object = nil)
          []
        end
      end
    end
  end
end

Faultline::RansackConfig.apply!
