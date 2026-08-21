# frozen_string_literal: true

require "rails/generators"

module Faultline
  module Generators
    class CustomizeGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc <<~DESC
        Generate customizable Faultline dashboard files.

        Creates modern views, host-app-integrated layout, Stimulus controller,
        and initializer patches for your Rails application.

        Usage:
          rails generate faultline:customize
          rails generate faultline:customize --layout-only
          rails generate faultline:customize --views-only
          rails generate faultline:customize --stimulus-only
          rails generate faultline:customize --initializer-only
      DESC

      class_option :layout_only, type: :boolean, default: false, desc: "Only generate the layout"
      class_option :views_only, type: :boolean, default: false, desc: "Only generate the views"
      class_option :stimulus_only, type: :boolean, default: false, desc: "Only generate the Stimulus controller"
      class_option :initializer_only, type: :boolean, default: false, desc: "Only generate the initializer patches"
      class_option :force, type: :boolean, default: false, desc: "Overwrite existing files"

      def generate_layout
        return unless generate_all? || options[:layout_only]

        template "views/layouts/faultline/application.html.erb",
                 "app/views/layouts/faultline/application.html.erb"
      end

      def generate_views
        return unless generate_all? || options[:views_only]

        template "views/faultline/logged_exceptions/index.html.erb",
                 "app/views/faultline/logged_exceptions/index.html.erb"

        template "views/faultline/logged_exceptions/_exceptions.html.erb",
                 "app/views/faultline/logged_exceptions/_exceptions.html.erb"

        template "views/faultline/logged_exceptions/_show.html.erb",
                 "app/views/faultline/logged_exceptions/_show.html.erb"
      end

      def generate_stimulus
        return unless generate_all? || options[:stimulus_only]

        template "javascript/controllers/faultline_controller.js",
                 "app/javascript/controllers/faultline_controller.js"

        run "bin/rails stimulus:manifest:update", capture: true if File.exist?("bin/rails")
      end

      def generate_initializer_patches
        return unless generate_all? || options[:initializer_only]

        append_to_file "config/initializers/faultline.rb" do
          "\n# --- Faultline Customize Generator Patches ---\n" \
          "\n" \
          "# Make host app helpers available in faultline views.\n" \
          "# Uncomment the helpers your app defines:\n" \
          "# Faultline::LoggedExceptionsController.helper HeroiconHelper\n" \
          "# Faultline::LoggedExceptionsController.helper ApplicationHelper\n" \
          "\n" \
          "# Fix for Rails 8.1+: params_filters must return plain hashes.\n" \
          "# This is applied automatically by the gem (v0.5.1+).\n" \
          "# Uncomment below if needed:\n" \
          "# Faultline::LoggedExceptionsController.class_eval do\n" \
          "#   private\n" \
          "#   def params_filters\n" \
          "#     result = {}\n" \
          "#     result[:q] = params[:q].to_unsafe_h if params[:q].present?\n" \
          "#     result[:query] = params[:query] if params[:query].present?\n" \
          "#     result[:date_ranges_filter] = params[:date_ranges_filter] if params[:date_ranges_filter].present?\n" \
          "#     result[:exception_names_filter] = params[:exception_names_filter] if params[:exception_names_filter].present?\n" \
          "#     result[:controller_actions_filter] = params[:controller_actions_filter] if params[:controller_actions_filter].present?\n" \
          "#     result\n" \
          "#   end\n" \
          "# end\n"
        end
      end

      def display_post_install
        return unless generate_all?

        say ""
        say "Faultline customization files generated!", :green
        say ""
        say "Generated files:"
        say "  - app/views/layouts/faultline/application.html.erb (host-app layout)"
        say "  - app/views/faultline/logged_exceptions/index.html.erb"
        say "  - app/views/faultline/logged_exceptions/_exceptions.html.erb"
        say "  - app/views/faultline/logged_exceptions/_show.html.erb"
        say "  - app/javascript/controllers/faultline_controller.js"
        say ""
        say "Next steps:"
        say "  1. Edit the layout to match your host app's navigation"
        say "  2. If using Tailwind, add to your CSS source paths:"
        say '     @source "path/to/faultline/app/views/**/*.erb";'
        say "  3. Run: bin/rails stimulus:manifest:update"
        say ""
      end

      private

      def generate_all?
        !options[:layout_only] && !options[:views_only] &&
          !options[:stimulus_only] && !options[:initializer_only]
      end
    end
  end
end
