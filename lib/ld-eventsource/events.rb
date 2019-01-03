
module LaunchDarklySSE
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
  #
  StreamEvent = Struct.new(:type, :data, :id)
end
