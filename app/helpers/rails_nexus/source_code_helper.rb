# frozen_string_literal: true

module RailsNexus
  module SourceCodeHelper
    # Parse a backtrace line into components
    # Returns { file: String, line: Integer, method: String, gem: String } or nil
    def parse_backtrace_line(line)
      return nil if line.blank?

      # Match standard Ruby backtrace: "path/to/file.rb:123:in `method_name'"
      if line =~ %r{\A(.+?):(\d+)(?::in `(.+?)')?\z}
        {
          file: $1,
          line: $2.to_i,
          method: $3
        }
      end
    end

    # Read source code snippet around a specific line
    # Returns { lines: Array, file: String, from_line: Integer, to_line: Integer, error_line: Integer }
    def read_source_snippet(file_path, error_line, context_lines: 5)
      return nil unless file_path.present? && File.exist?(file_path)

      total_lines = File.foreach(file_path).count
      from_line = [error_line - context_lines, 1].max
      to_line = [error_line + context_lines, total_lines].min

      lines = []
      current_line = 0

      File.foreach(file_path) do |raw_line|
        current_line += 1
        break if current_line > to_line
        next if current_line < from_line

        lines << {
          number: current_line,
          content: raw_line.rstrip,
          is_error: current_line == error_line
        }
      end

      {
        lines: lines,
        file: file_path,
        from_line: from_line,
        to_line: to_line,
        error_line: error_line
      }
    end

    # Get git blame for a specific line
    # Returns { sha: String, author: String, date: String, message: String }
    def git_blame_for_line(file_path, line_number)
      return nil unless file_path.present? && line_number.present?
      return nil unless File.exist?(file_path)
      return nil unless system("git", "rev-parse", "--git-dir", File.dirname(file_path), [:out, :err] => File::NULL)

      # Get blame for single line
      blame_output = `git -C "#{File.dirname(file_path)}" blame -L #{line_number},#{line_number} -p "#{File.basename(file_path)}" 2>/dev/null`
      return nil unless $?.success?

      # Parse porcelain blame output
      result = {}
      blame_output.each_line do |line|
        case line
        when /^([0-9a-f]{40})\s+(\d+)\s+(\d+)/
          result[:sha] = $1[0..6]
          result[:line] = $3.to_i
        when /^author\s+(.+)/
          result[:author] = $1.strip
        when /^author-time\s+(\d+)/
          result[:date] = Time.at($1.to_i).strftime("%Y-%m-%d")
        when /^summary\s+(.+)/
          result[:message] = $1.strip
        when /^filename\s+(.+)/
          result[:filename] = $1.strip
        end
      end

      result.presence
    end

    # Get source code with git blame for multiple backtrace lines
    # Returns array of { backtrace_line:, parsed:, source:, blame: }
    def source_with_blame(backtrace_lines, limit: 10)
      return [] if backtrace_lines.blank?

      backtrace_lines.first(limit).filter_map do |line|
        parsed = parse_backtrace_line(line)
        next nil unless parsed

        source = read_source_snippet(parsed[:file], parsed[:line])
        blame = git_blame_for_line(parsed[:file], parsed[:line])

        {
          backtrace_line: line,
          parsed: parsed,
          source: source,
          blame: blame,
          is_app_code: parsed[:file]&.start_with?(Rails.root.to_s)
        }
      end
    end
  end
end
