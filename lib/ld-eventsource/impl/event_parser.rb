require "ld-eventsource/events"

module LaunchDarklySSE
  module Impl
    #
    # Indicates that the SSE server sent a `retry:` field to override the client's reconnection
    # interval. You will only see this class if you use {EventParser} directly; {Client} will
    # consume it and not pass it on.
    #
    # @!attribute milliseconds
    #   @return [Int] the new reconnect interval in milliseconds
    #
    SetRetryInterval = Struct.new(:milliseconds)

    #
    # Accepts lines of text via an enumerator, and parses them into SSE messages. You will not need
    # to use this directly if you are using {Client}, but it may be useful for testing.
    #
    class EventParser
      #
      # Constructs an instance of EventParser.
      #
      # @param [Enumerator] lines  an enumerator that will yield one line of text at a time
      #
      def initialize(lines)
        @lines = lines
        reset_buffers
      end

      # Generator that parses the input iterator and returns instances of {StreamEvent} or {SetRetryInterval}.
      def items
        Enumerator.new do |gen|
          @lines.each do |line|
            line.chomp!
            if line.empty?
              event = maybe_create_event
              reset_buffers
              gen.yield event if !event.nil?
            else
              case line
                when /^(\w+): ?(.*)$/
                  item = process_field($1, $2)
                  gen.yield item if !item.nil?
              end
            end
          end
        end
      end

      private

      def reset_buffers
        @id = nil
        @type = nil
        @data = ""
      end

      def process_field(name, value)
        case name
          when "event"
            @type = value.to_sym
          when "data"
            @data << "\n" if !@data.empty?
            @data << value
          when "id"
            @id = value
          when "retry"
            if /^(?<num>\d+)$/ =~ value
              return SetRetryInterval.new(num.to_i)
            end
        end
        nil
      end

      def maybe_create_event
        return nil if @data.empty?
        StreamEvent.new(@type || :message, @data, @id)
      end
    end
  end
end
