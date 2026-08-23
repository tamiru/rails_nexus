# frozen_string_literal: true

module RailsNexus
  class SourceCodeController < ApplicationController
    include SourceCodeHelper

    # GET /rails_nexus/source_code?file=...&line=...
    def show
      file_path = params[:file]
      line_number = params[:line]&.to_i

      if file_path.blank? || line_number.blank?
        render json: { error: "file and line parameters required" }, status: :bad_request
        return
      end

      # Security: only allow reading files within Rails.root
      begin
        real_path = File.realpath(file_path)
        unless real_path.start_with?(Rails.root.to_s)
          render json: { error: "Access denied" }, status: :forbidden
          return
        end
      rescue Errno::ENOENT
        render json: { error: "File not found" }, status: :not_found
        return
      end

      source = read_source_snippet(file_path, line_number, context_lines: params[:context]&.to_i || 5)
      blame = git_blame_for_line(file_path, line_number)

      if source
        render json: { source: source, blame: blame }
      else
        render json: { error: "Could not read file" }, status: :not_found
      end
    end
  end
end
