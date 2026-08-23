# frozen_string_literal: true

require "rails/generators"

module RailsNexus
  module Generators
    class CustomizeGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc <<~DESC
        Generate customizable RailsNexus dashboard files.

        Creates modern views, host-app-integrated layout, Stimulus controller,
        and initializer patches for your Rails application.

        Usage:
          rails generate rails_nexus:customize
          rails generate rails_nexus:customize --layout-only
          rails generate rails_nexus:customize --views-only
          rails generate rails_nexus:customize --stimulus-only
          rails generate rails_nexus:customize --initializer-only
      DESC

      class_option :layout_only, type: :boolean, default: false, desc: "Only generate the layout"
      class_option :views_only, type: :boolean, default: false, desc: "Only generate the views"
      class_option :stimulus_only, type: :boolean, default: false, desc: "Only generate the Stimulus controller"
      class_option :initializer_only, type: :boolean, default: false, desc: "Only generate the initializer patches"
      class_option :force, type: :boolean, default: false, desc: "Overwrite existing files"

      def generate_layout
        return unless generate_all? || options[:layout_only]

        template "views/layouts/rails_nexus/application.html.erb",
                 "app/views/layouts/rails_nexus/application.html.erb"
      end

      def generate_views
        return unless generate_all? || options[:views_only]

        template "views/rails_nexus/logged_exceptions/index.html.erb",
                 "app/views/rails_nexus/logged_exceptions/index.html.erb"

        template "views/rails_nexus/logged_exceptions/_exceptions.html.erb",
                 "app/views/rails_nexus/logged_exceptions/_exceptions.html.erb"

        template "views/rails_nexus/logged_exceptions/_show.html.erb",
                 "app/views/rails_nexus/logged_exceptions/_show.html.erb"
      end

      def generate_stimulus
        return unless generate_all? || options[:stimulus_only]

        target_dir = "app/javascript/rails_nexus/controllers"

        template "javascript/controllers/rails_nexus_controller.js",
                 "#{target_dir}/rails_nexus_controller.js"
        template "javascript/controllers/rails_nexus_detail_controller.js",
                 "#{target_dir}/rails_nexus_detail_controller.js"
        template "javascript/controllers/rails_nexus_theme_controller.js",
                 "#{target_dir}/rails_nexus_theme_controller.js"
        template "javascript/controllers/rails_nexus_sidebar_controller.js",
                 "#{target_dir}/rails_nexus_sidebar_controller.js"

        # Create a standalone manifest under rails_nexus/ so it works
        # with both esbuild (jsbundling) and importmap.
        # This avoids conflict with stimulus:manifest:update which
        # only scans app/javascript/controllers/.
        create_file "app/javascript/rails_nexus/index.js" do
          <<~JS
            import { application } from "../controllers/application"

            import RailsNexusController from "./controllers/rails_nexus_controller"
            application.register("rails_nexus", RailsNexusController)

            import RailsNexusDetailController from "./controllers/rails_nexus_detail_controller"
            application.register("rails_nexus-detail", RailsNexusDetailController)

            import RailsNexusThemeController from "./controllers/rails_nexus_theme_controller"
            application.register("rails_nexus-theme", RailsNexusThemeController)

            import RailsNexusSidebarController from "./controllers/rails_nexus_sidebar_controller"
            application.register("rails_nexus-sidebar", RailsNexusSidebarController)
          JS
        end

        # Inject import into application.js if not already present
        app_js = "app/javascript/application.js"
        if File.exist?(app_js)
          content = File.read(app_js)
          unless content.include?("rails_nexus")
            inject_into_file app_js,
              'import "./rails_nexus"
',
              after: /import.*controllers.*\n/
          end
        end
      end

      def generate_initializer_patches
        return unless generate_all? || options[:initializer_only]

        append_to_file "config/initializers/rails_nexus.rb" do
          "\n# --- RailsNexus Customize Generator Patches ---\n" \
          "\n" \
          "# Make host app helpers available in rails_nexus views.\n" \
          "# Uncomment the helpers your app defines:\n" \
          "# RailsNexus::LoggedExceptionsController.helper HeroiconHelper\n" \
          "# RailsNexus::LoggedExceptionsController.helper ApplicationHelper\n" \
          "\n" \
          "# Fix for Rails 8.1+: params_filters must return plain hashes.\n" \
          "# This is applied automatically by the gem (v0.5.1+).\n" \
          "# Uncomment below if needed:\n" \
          "# RailsNexus::LoggedExceptionsController.class_eval do\n" \
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
        say "RailsNexus customization files generated!", :green
        say ""
        say "Generated files:"
        say "  - app/views/layouts/rails_nexus/application.html.erb (host-app layout)"
        say "  - app/views/rails_nexus/logged_exceptions/index.html.erb"
        say "  - app/views/rails_nexus/logged_exceptions/_exceptions.html.erb"
        say "  - app/views/rails_nexus/logged_exceptions/_show.html.erb"
        say "  - app/javascript/rails_nexus/controllers/rails_nexus_controller.js"
        say "  - app/javascript/rails_nexus/controllers/rails_nexus_detail_controller.js"
        say "  - app/javascript/rails_nexus/controllers/rails_nexus_theme_controller.js"
        say "  - app/javascript/rails_nexus/controllers/rails_nexus_sidebar_controller.js"
        say ""
        say "Next steps:"
        say "  1. Edit the layout to match your host app's navigation"
        say "  2. If using Tailwind, add to your CSS source paths:"
        say '     @source "path/to/rails_nexus/app/views/**/*.erb";'
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
