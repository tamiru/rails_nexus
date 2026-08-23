# frozen_string_literal: true

module RailsNexus
  # Storm Protection: Circuit breaker + adaptive sampling
  # Prevents error floods from crashing the app with DB writes
  module StormProtection
    # Default thresholds
    DEFAULT_PER_PROCESS_THRESHOLD = 50  # errors per second per process
    DEFAULT_GLOBAL_THRESHOLD = 200       # errors per second globally
    DEFAULT_COOLDOWN_SECONDS = 60        # circuit breaker cooldown
    DEFAULT_SAMPLE_RATE_CALM = 1.0       # 100% capture when calm
    DEFAULT_SAMPLE_RATE_STORM = 0.1      # 10% capture during storm

    class << self
      attr_reader :circuit_open, :error_counts, :last_reset

      def enabled?
        RailsNexus.configuration.storm_protection_enabled
      end

      def threshold
        RailsNexus.configuration.storm_threshold_per_second || DEFAULT_PER_PROCESS_THRESHOLD
      end

      def cooldown
        RailsNexus.configuration.storm_cooldown_seconds || DEFAULT_COOLDOWN_SECONDS
      end

      # Check if we should capture this error
      # Returns true if allowed, false if shed
      def allow_capture?
        return true unless enabled?

        reset_counts_if_needed

        # If circuit is open (storm detected), use sampling
        if circuit_open?
          return should_sample?
        end

        # Increment count and check threshold
        @error_counts[:total] += 1
        @error_counts[:current_second] += 1

        if @error_counts[:current_second] >= threshold
          open_circuit!
          return should_sample?
        end

        true
      end

      # Record that an error was captured
      def record_captured
        @error_counts[:captured] += 1
      end

      # Record that an error was shed
      def record_shed
        @error_counts[:shed] += 1
      end

      # Get current stats
      def stats
        reset_counts_if_needed
        {
          enabled: enabled?,
          circuit_open: circuit_open?,
          errors_this_second: @error_counts[:current_second] || 0,
          threshold: threshold,
          total_errors: @error_counts[:total] || 0,
          total_captured: @error_counts[:captured] || 0,
          total_shed: @error_counts[:shed] || 0,
          last_reset: @last_reset,
          sample_rate: circuit_open? ? DEFAULT_SAMPLE_RATE_STORM : DEFAULT_SAMPLE_RATE_CALM
        }
      end

      # Reset circuit (manual or after cooldown)
      def reset!
        @circuit_open = false
        @error_counts = { total: 0, current_second: 0, captured: 0, shed: 0 }
        @last_reset = Time.now
        @second_window = Time.now.to_i
      end

      private

      def circuit_open?
        return false unless @circuit_open

        # Auto-reset after cooldown
        if Time.now - @circuit_open_at > cooldown
          reset!
          return false
        end

        true
      end

      def open_circuit!
        @circuit_open = true
        @circuit_open_at = Time.now
        Rails.logger.warn("[RailsNexus] Storm protection: circuit opened at #{@error_counts[:current_second]} errors/sec")
      end

      def reset_counts_if_needed
        current_second = Time.now.to_i
        if current_second != @second_window
          @error_counts[:current_second] = 0
          @second_window = current_second
        end
      end

      def should_sample?
        # Keep 10% of errors during storm
        rand < DEFAULT_SAMPLE_RATE_STORM
      end
    end

    # Initialize on load
    reset!
  end
end
