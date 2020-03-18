
module SSE
  module Impl
    #
    # A simple backoff algorithm that can reset itself after a given interval has passed without errors.
    # A random jitter of up to -50% is applied to each interval.
    #
    class Backoff
      #
      # Constructs a backoff counter.
      #
      # @param [Float] base_interval  the minimum value
      # @param [Float] max_interval  the maximum value
      # @param [Float] reconnect_reset_interval  the interval will be reset to the minimum if this number of
      #   seconds elapses between the last call to {#mark_success} and the next call to {#next_interval}
      #
      def initialize(base_interval, max_interval, reconnect_reset_interval: 60)
        @base_interval = base_interval
        @max_interval = max_interval
        @reconnect_reset_interval = reconnect_reset_interval
        @attempts = 0
        @last_good_time = nil
        @jitter_rand = Random.new
      end

      #
      # The minimum value for the backoff interval.
      #
      attr_accessor :base_interval

      #
      # Computes the next interval value.
      #
      # @return [Float]  the next interval in seconds
      #
      def next_interval
        if !@last_good_time.nil?
          good_duration = Time.now.to_f - @last_good_time
          @attempts = 0 if good_duration >= @reconnect_reset_interval
        end
        @last_good_time = nil
        target = ([@base_interval * (2 ** @attempts), @max_interval].min).to_f
        @attempts += 1
        (target / 2) + @jitter_rand.rand(target / 2)
      end

      #
      # Marks the current time as being the beginning of a valid connection state, resetting the timer
      # that measures how long the state has been valid.
      #
      def mark_success
        @last_good_time = Time.now.to_f
      end
    end
  end
end
