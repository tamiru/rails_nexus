# frozen_string_literal: true

module RailsNexus
  class SourceCodeController < ApplicationController
    include SourceCodeHelper

    # GET /rails_nexus/source_code?file=...&line=...
    def show
      file_path = params[:file]
      line_number = Integer(params[:line], exception: false)

      if file_path.blank? || !line_number&.positive?
        render json: { error: "file and line parameters required" }, status: :bad_request
        return
      end

      resolved_path = resolve_source_path(file_path)
      unless resolved_path
        render json: { error: "File not found or access denied" }, status: :not_found
        return
      end

      requested_context = Integer(params[:context], exception: false) || 5
      context_lines = requested_context.clamp(0, 50)
      source = read_source_snippet(resolved_path, line_number, context_lines: context_lines)
      blame = git_blame_for_line(resolved_path, line_number)

      if source
        render json: { source: source, blame: blame }
      else
        render json: { error: "Could not read file" }, status: :not_found
      end
    end
  end
end
