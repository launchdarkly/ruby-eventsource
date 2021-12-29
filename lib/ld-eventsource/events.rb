
module SSE
  #
  # Server-Sent Event type used by {Client}. Use {Client#on_event} to receive events.
  #
  # @!attribute type
  #   @return [Symbol] the string that appeared after `event:` in the stream;
  #     defaults to `:message` if `event:` was not specified, will never be nil
  # @!attribute data
  #   @return [String] the string that appeared after `data:` in the stream;
  #     if there were multiple `data:` lines, they are concatenated with newlines
  # @!attribute id
  #   @return [String] the string that appeared after `id:` in the stream if any, or nil
  # @!attribute last_event_id
  #   @return [String] the `id:` value that was most recently seen in an event from
  #     this stream; this differs from the `id` property in that it retains the same value
  #     in subsequent events if they do not provide their own `id:`
  #
  StreamEvent = Struct.new(:type, :data, :id, :last_event_id)
end
