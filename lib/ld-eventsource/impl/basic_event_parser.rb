require "ld-eventsource/events"

module SSE
  module Impl
    class BasicEventParser

      def initialize(chunks)
        @chunks = chunks
      end

      # Generator that parses the input iterator and returns instances of {StreamEvent} or {SetRetryInterval}.
      def items
        Enumerator.new do |gen|
          @chunks.each do |chunk|
            item = StreamEvent.new(chunk.nil? ? :final_message : :message, chunk, nil, nil)
            gen.yield item
          end
        end
      end
    end
  end
end