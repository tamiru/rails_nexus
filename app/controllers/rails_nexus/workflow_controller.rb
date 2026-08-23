module RailsNexus
  class WorkflowController < ApplicationController
    before_action :find_exception

    # POST /rails_nexus/logged_exceptions/:id/assign
    def assign
      @exception.assign_to(params[:assigned_to], author: current_author)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("workflow-panel", partial: "rails_nexus/logged_exceptions/workflow_panel", locals: { exception: @exception }) }
        format.html { redirect_back fallback_location: logged_exception_path(@exception), notice: "Assigned to #{params[:assigned_to]}" }
        format.json { render json: { status: "ok", assigned_to: @exception.assigned_to } }
      end
    end

    # POST /rails_nexus/logged_exceptions/:id/priority
    def set_priority
      @exception.set_priority(params[:priority], author: current_author)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("workflow-panel", partial: "rails_nexus/logged_exceptions/workflow_panel", locals: { exception: @exception }) }
        format.html { redirect_back fallback_location: logged_exception_path(@exception), notice: "Priority set to #{params[:priority]}" }
        format.json { render json: { status: "ok", priority: @exception.priority } }
      end
    end

    # POST /rails_nexus/logged_exceptions/:id/snooze
    def snooze
      duration = parse_duration(params[:duration])
      @exception.snooze(duration, author: current_author)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("workflow-panel", partial: "rails_nexus/logged_exceptions/workflow_panel", locals: { exception: @exception }) }
        format.html { redirect_back fallback_location: logged_exception_path(@exception), notice: "Snoozed for #{duration.inspect}" }
        format.json { render json: { status: "ok", snoozed_until: @exception.snoozed_until } }
      end
    end

    # POST /rails_nexus/logged_exceptions/:id/mute
    def mute
      @exception.mute!(author: current_author)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("workflow-panel", partial: "rails_nexus/logged_exceptions/workflow_panel", locals: { exception: @exception }) }
        format.html { redirect_back fallback_location: logged_exception_path(@exception), notice: "Muted" }
        format.json { render json: { status: "ok", muted: @exception.muted } }
      end
    end

    # POST /rails_nexus/logged_exceptions/:id/unmute
    def unmute
      @exception.unmute!(author: current_author)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("workflow-panel", partial: "rails_nexus/logged_exceptions/workflow_panel", locals: { exception: @exception }) }
        format.html { redirect_back fallback_location: logged_exception_path(@exception), notice: "Unmuted" }
        format.json { render json: { status: "ok", muted: @exception.muted } }
      end
    end

    # POST /rails_nexus/logged_exceptions/:id/comment
    def add_comment
      @exception.add_comment(author: current_author, body: params[:body], comment_type: params[:comment_type] || "comment")
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("comments-list", partial: "rails_nexus/logged_exceptions/comments_list", locals: { exception: @exception }) }
        format.html { redirect_back fallback_location: logged_exception_path(@exception), notice: "Comment added" }
        format.json { render json: { status: "ok", comments_count: @exception.comments_count } }
      end
    end

    private

    def find_exception
      @exception = RailsNexus::LoggedException.find(params[:id])
    end

    def current_author
      # Try to get current user from the host app's auth system
      if respond_to?(:current_user, true) && current_user
        current_user.respond_to?(:email) ? current_user.email : current_user.to_s
      elsif RailsNexus.configuration.current_user_block
        RailsNexus.configuration.current_user_block.call(self)
      else
        "anonymous"
      end
    end

    def parse_duration(str)
      case str.to_s
      when /(\d+)\s*hour/
        $1.to_i.hours
      when /(\d+)\s*day/
        $1.to_i.days
      when /(\d+)\s*week/
        $1.to_i.weeks
      else
        24.hours # default: 1 day
      end
    end
  end
end
