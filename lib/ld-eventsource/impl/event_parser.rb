require "ld-eventsource/events"

module SSE
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
      # @param [Enumerator] lines  an enumerator that will yield one line of text at a time;
      #   the lines should not include line terminators
      #
      def initialize(lines, last_event_id = nil)
        @lines = lines
        @last_event_id = last_event_id
        reset_buffers
      end

      # Generator that parses the input iterator and returns instances of {StreamEvent} or {SetRetryInterval}.
      def items
        Enumerator.new do |gen|
          @lines.each do |line|
            if line.empty?
              event = maybe_create_event
              reset_buffers
              gen.yield event unless event.nil?
            elsif (pos = line.index(':'))
              name = line.slice(0...pos)

              pos += 1  # skip colon
              pos += 1 if pos < line.length && line[pos] == ' '  # skip optional single space, per SSE spec
              value = line.slice(pos..-1)

              item = process_field(name, value)
              gen.yield item unless item.nil?
            else
              # Handle field with no colon - treat as having empty value
              # According to SSE spec, a line like "data" should be treated as "data:"
              item = process_field(line, "")
              gen.yield item unless item.nil?
            end
          end
        end
      end

      private

      def reset_buffers
        @id = nil
        @type = nil
        @data = ""
        @have_data = false
      end

      def process_field(name, value)
        case name
          when "event"
            @type = value.to_sym
          when "data"
            if @have_data
              @data << "\n" << value
            else
              @data = value
            end
            @have_data = true
          when "id"
            unless value.include?("\x00")
              @id = value
              @last_event_id = value
            end
          when "retry"
            if /^(?<num>\d+)$/ =~ value
              return SetRetryInterval.new(num.to_i)
            end
        end
        nil
      end

      def maybe_create_event
        return nil unless @have_data
        StreamEvent.new(@type || :message, @data, @id, @last_event_id)
      end
    end
  end
end
