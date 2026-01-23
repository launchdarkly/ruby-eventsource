
module SSE
  #
  # Exception classes used by the SSE client.
  #
  module Errors
    #
    # An exception class representing an HTTP error response. This can be passed to the error
    # handler specified in {Client#on_error}.
    #
    class HTTPStatusError < StandardError
      def initialize(status, message, headers = nil)
        @status = status
        @message = message
        @headers = headers
        super("HTTP error #{status}")
      end

      # The HTTP status code.
      # @return [Int]
      attr_reader :status

      # The response body, if any.
      # @return [String]
      attr_reader :message

      # The HTTP response headers, if any.
      #
      # The headers object uses case-insensitive keys (via the http gem's HTTP::Headers).
      #
      # @return [Hash, nil] the response headers, or nil if not available
      attr_reader :headers
    end

    #
    # An exception class representing an invalid HTTP content type. This can be passed to the error
    # handler specified in {Client#on_error}.
    #
    class HTTPContentTypeError < StandardError
      def initialize(type, headers = nil)
        @content_type = type
        @headers = headers
        super("invalid content type \"#{type}\"")
      end

      # The HTTP content type.
      # @return [String]
      attr_reader :type

      # The HTTP response headers, if any.
      #
      # The headers object uses case-insensitive keys (via the http gem's HTTP::Headers).
      #
      # @return [Hash, nil] the response headers, or nil if not available
      attr_reader :headers
    end

    #
    # An exception class indicating that an HTTP proxy server returned an error.
    #
    class HTTPProxyError < StandardError
      def initialize(status)
        @status = status
        super("proxy server returned error #{status}")
      end

      # The HTTP status code.
      # @return [Int]
      attr_reader :status
    end

    #
    # An exception class indicating that the client dropped the connection due to a read timeout.
    # This means that the number of seconds specified by `read_timeout` in {Client#initialize}
    # elapsed without receiving any data from the server.
    #
    class ReadTimeoutError < StandardError
      def initialize(interval)
        super("no data received in #{interval} seconds")
      end
    end
  end
end
