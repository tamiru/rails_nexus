# frozen_string_literal: true

module RailsNexus
  module DatabaseAdapter
    module_function

    def family(connection = ActiveRecord::Base.connection)
      name = connection.adapter_name.to_s.downcase
      return :postgresql if name.include?("postgres")
      return :mysql if name.include?("mysql") || name.include?("trilogy")
      return :sqlite if name.include?("sqlite")

      :unsupported
    end

    def time_bucket_expression(column: "created_at", period: :hour, connection: ActiveRecord::Base.connection)
      column = connection.quote_column_name(column)

      case [family(connection), period.to_sym]
      when [:postgresql, :hour] then "TO_CHAR(DATE_TRUNC('hour', #{column}), 'YYYY-MM-DD HH24:00')"
      when [:mysql, :hour] then "DATE_FORMAT(#{column}, '%Y-%m-%d %H:00')"
      when [:sqlite, :hour] then "strftime('%Y-%m-%d %H:00', #{column})"
      else
        raise NotImplementedError, "Time grouping is not supported by this database adapter"
      end
    end

    def time_component_expression(column: "created_at", component:, connection: ActiveRecord::Base.connection)
      column = connection.quote_column_name(column)

      case [family(connection), component.to_sym]
      when [:postgresql, :hour] then "CAST(EXTRACT(HOUR FROM #{column}) AS INTEGER)"
      when [:mysql, :hour] then "HOUR(#{column})"
      when [:sqlite, :hour] then "CAST(strftime('%H', #{column}) AS INTEGER)"
      when [:postgresql, :weekday] then "CAST(EXTRACT(DOW FROM #{column}) AS INTEGER)"
      when [:mysql, :weekday] then "DAYOFWEEK(#{column}) - 1"
      when [:sqlite, :weekday] then "CAST(strftime('%w', #{column}) AS INTEGER)"
      else
        raise NotImplementedError, "Time component grouping is not supported by this database adapter"
      end
    end

    def database_version(connection = ActiveRecord::Base.connection)
      case family(connection)
      when :sqlite then connection.select_value("SELECT sqlite_version()")
      when :postgresql, :mysql then connection.select_value("SELECT version()")
      else "N/A"
      end
    rescue ActiveRecord::StatementInvalid
      "N/A"
    end
  end
end
