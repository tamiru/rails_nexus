# frozen_string_literal: true

module Faultline
  class LoggedExceptionsController < ApplicationController
    before_action :faultline_require_auth!

    helper_method :params_filters, :prev_exception, :next_exception

    def index
      load_exception_names
      load_controller_actions
      @q = ransack_search
      @exceptions = @q.result(distinct: true)
                      .paginate(page: params[:page], per_page: page_size)
      load_stats if Faultline.configuration.show_stats
    end

    def query
      load_exception_names
      load_controller_actions
      @q = ransack_search
      @exceptions = @q.result(distinct: true)
                      .paginate(page: params[:page], per_page: page_size)
      load_stats if Faultline.configuration.show_stats

      respond_to do |format|
        format.turbo_stream
        format.html { render :query }
      end
    end

    def feed
      @exceptions = LoggedException.all

      respond_to do |format|
        format.rss { render layout: false }
      end
    end

    def show
      @exception = LoggedException.find(params[:id])
      load_nav_exceptions if Faultline.configuration.enable_navigation
      load_exception_tabs

      respond_to do |format|
        format.turbo_stream
        format.html
      end
    end

    def destroy
      @exception = LoggedException.find(params[:id])
      @exception.destroy!

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to logged_exceptions_path, status: :see_other }
      end
    end

    def destroy_all
      exceptions = if params[:ids].present?
        LoggedException.where(id: params[:ids].to_s.split(","))
      else
        filtered_scope
      end
      exceptions.delete_all

      load_exception_names
      load_controller_actions
      @q = ransack_search
      @exceptions = @q.result(distinct: true)
                      .paginate(page: params[:page], per_page: page_size)

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to logged_exceptions_path(params_filters) }
      end
    end

    def clear
      LoggedException.delete_all

      load_exception_names
      load_controller_actions
      @q = ransack_search
      @exceptions = @q.result(distinct: true)
                      .paginate(page: params[:page], per_page: page_size)

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: faultline_root_path }
      end
    end

    private

    def faultline_require_auth!
      auth_block = Faultline.configuration.auth_block
      return if auth_block&.call(self)

      head :forbidden
    end

    def faultline_root_path
      main_app.respond_to?(:root_path) ? main_app.root_path : "/"
    end

    def page_size
      requested = params[:per_page].to_i
      options = Faultline.configuration.page_size_options
      options.include?(requested) ? requested : (Faultline.configuration.per_page || 30)
    end

    def ransack_search
      if defined?(Ransack)
        LoggedException.ransack(params[:q])
      else
        scope = filtered_scope
        Struct.new(:result).new(scope)
      end
    end

    def params_filters
      {
        q: params[:q],
        query: params[:query],
        date_ranges_filter: params[:date_ranges_filter],
        exception_names_filter: params[:exception_names_filter],
        controller_actions_filter: params[:controller_actions_filter],
        per_page: params[:per_page]
      }.compact
    end

    def filtered_scope
      exceptions = LoggedException.sorted
      exceptions = exceptions.where(id: params[:id]) if params[:id].present?
      exceptions = exceptions.message_like(params[:query]) if params[:query].present?
      exceptions = exceptions.days_old(params[:date_ranges_filter]) if params[:date_ranges_filter].present?
      exceptions = exceptions.by_exception_class(params[:exception_names_filter]) if params[:exception_names_filter].present?

      if params[:controller_actions_filter].present?
        controller_name, action_name = params[:controller_actions_filter].split("/", 2)
        exceptions = exceptions.by_controller(controller_name.underscore)
        exceptions = exceptions.by_action(action_name.downcase) if action_name.present?
      end

      exceptions
    end

    def load_exception_names
      @exception_names = LoggedException.class_names
    end

    def load_controller_actions
      @controller_actions = LoggedException.controller_actions
    end

    def load_stats
      total = LoggedException.count
      today = LoggedException.where("created_at >= ?", Time.zone.today.beginning_of_day).count
      week = LoggedException.where("created_at >= ?", 7.days.ago.beginning_of_day).count
      yesterday = LoggedException.where("created_at >= ?", 1.day.ago.beginning_of_day)
                                 .where("created_at < ?", Time.zone.today.beginning_of_day).count

      @stats = {
        total: total,
        today: today,
        this_week: week,
        yesterday: yesterday,
        top_classes: LoggedException.group(:exception_class).limit(5).count,
        top_controllers: LoggedException.group(:controller_name).limit(5).count
      }
    end

    def load_nav_exceptions
      scope = filtered_scope.sorted
      ids = scope.pluck(:id)
      current_idx = ids.index(@exception.id)

      if current_idx
        @prev_exception_id = ids[current_idx + 1]
        @next_exception_id = ids[current_idx - 1]
      end
    end

    def prev_exception
      return nil unless @prev_exception_id
      OpenStruct.new(id: @prev_exception_id)
    end

    def next_exception
      return nil unless @next_exception_id
      OpenStruct.new(id: @next_exception_id)
    end

    def load_exception_tabs
      @exception_tabs = {
        overview: true,
        backtrace: @exception.backtrace.present?,
        request: @exception.request.present?,
        environment: @exception.environment.present?,
        user_info: @exception.user_info.present?
      }
    end
  end
end
