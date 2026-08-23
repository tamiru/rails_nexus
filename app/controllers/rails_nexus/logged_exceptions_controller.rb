# frozen_string_literal: true

module RailsNexus
  class LoggedExceptionsController < ApplicationController
    RANSACK_FILTERS = %i[
      action_name_cont assigned_to_cont controller_name_cont created_at_gteq created_at_lteq
      exception_class_cont fingerprint_cont message_cont
      message_or_exception_class_or_controller_name_or_action_name_cont
      occurrence_count_gteq platform_eq priority_eq s
    ].freeze

    helper_method :exception_feature?, :params_filters, :prev_exception, :next_exception

    def index
      load_exception_index
    end

    def query
      load_exception_index

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
      load_nav_exceptions if RailsNexus.configuration.enable_navigation
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
        ransack_search.result(distinct: false)
      end
      exceptions.delete_all

      load_exception_index

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to logged_exceptions_path(params_filters) }
      end
    end

    def clear
      LoggedException.delete_all

      load_exception_index

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: rails_nexus_root_path }
      end
    end

    private

    def rails_nexus_root_path
      main_app.respond_to?(:root_path) ? main_app.root_path : "/"
    end

    def page_size
      requested = params[:per_page].to_i
      options = RailsNexus.configuration.page_size_options
      options.include?(requested) ? requested : (RailsNexus.configuration.per_page || 30)
    end

    def load_exception_index
      load_filter_options
      @q = ransack_search
      load_stats if RailsNexus.configuration.show_stats
      @pagy, @exceptions = pagy(@q.result(distinct: true), items: page_size)
    rescue Pagy::OverflowError
      @pagy, @exceptions = pagy(@q.result(distinct: true), page: 1, items: page_size)
    end

    def ransack_search
      search = filtered_scope.ransack(ransack_params)
      search.sorts = "created_at desc" if search.sorts.empty?
      search
    end

    def ransack_params
      return {} unless params[:q].respond_to?(:permit)

      params.require(:q).permit(*RANSACK_FILTERS)
    end

    def params_filters
      {
        q: ransack_params.to_h.presence,
        query: params[:query],
        date_ranges_filter: params[:date_ranges_filter],
        exception_names_filter: params[:exception_names_filter],
        platform_filter: params[:platform_filter],
        controller_actions_filter: params[:controller_actions_filter],
        status_filter: params[:status_filter],
        per_page: params[:per_page]
      }.compact
    end

    def filtered_scope
      exceptions = LoggedException.all
      exceptions = exceptions.where(id: params[:id]) if params[:id].present?
      exceptions = exceptions.message_like(params[:query]) if params[:query].present?
      exceptions = exceptions.days_old(params[:date_ranges_filter]) if params[:date_ranges_filter].present?
      exceptions = exceptions.by_exception_class(params[:exception_names_filter]) if params[:exception_names_filter].present?
      exceptions = exceptions.by_platform(params[:platform_filter]) if params[:platform_filter].present? && exception_feature?(:platform)

      if params[:controller_actions_filter].present?
        controller_name, action_name = params[:controller_actions_filter].split("/", 2)
        exceptions = exceptions.by_controller(controller_name)
        exceptions = exceptions.by_action(action_name) if action_name.present?
      end

      apply_status_filter(exceptions)
    end

    def load_filter_options
      @exception_names = LoggedException.class_names
      @controller_actions = LoggedException.controller_actions
      @assignees = if exception_feature?(:assigned_to)
        LoggedException.where.not(assigned_to: [nil, ""]).distinct.order(:assigned_to).pluck(:assigned_to)
      else
        []
      end
    end

    def apply_status_filter(scope)
      return scope if params[:status_filter].blank?

      case params[:status_filter]
      when "active"
        exception_feature?(:muted) && exception_feature?(:snoozed_until) ? scope.active : scope
      when "muted"
        exception_feature?(:muted) ? scope.muted : scope
      when "snoozed"
        exception_feature?(:snoozed_until) ? scope.snoozed : scope
      when "unassigned"
        exception_feature?(:assigned_to) ? scope.unassigned : scope
      else
        scope
      end
    end

    def exception_feature?(column)
      LoggedException.column_names.include?(column.to_s)
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
      Struct.new(:id).new(@prev_exception_id)
    end

    def next_exception
      return nil unless @next_exception_id
      Struct.new(:id).new(@next_exception_id)
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
