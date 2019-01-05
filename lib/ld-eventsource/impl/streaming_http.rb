require "ld-eventsource/errors"

require "concurrent/atomics"
require "http_tools"
require "socketry"

module SSE
  module Impl
    #
    # Wrapper around a socket providing a simplified HTTP request-response cycle including streaming.
    # The socket is created and managed by Socketry, which we use so that we can have a read timeout.
    #
    class StreamingHTTPConnection
      attr_reader :status, :headers

      #
      # Opens a new connection.
      #
      # @param [String] uri  the URI to connect o
      # @param [String] proxy  the proxy server URI, if any
      # @param [Hash] headers  request headers
      # @param [Float] connect_timeout  connection timeout
      # @param [Float] read_timeout  read timeout
      #
      def initialize(uri, proxy: nil, headers: {}, connect_timeout: nil, read_timeout: nil)
        @socket = HTTPConnectionFactory.connect(uri, proxy, connect_timeout, read_timeout)
        @socket.write(build_request(uri, headers))
        @reader = HTTPResponseReader.new(@socket, read_timeout)
        @status = @reader.status
        @headers = @reader.headers
        @closed = Concurrent::AtomicBoolean.new(false)
      end

      #
      # Closes the connection.
      #
      def close
        if @closed.make_true
          @socket.close if @socket
          @socket = nil
        end
      end
      
      #
      # Generator that returns one line of the response body at a time (delimited by \r, \n,
      # or \r\n) until the response is fully consumed or the socket is closed.
      #
      def read_lines
        @reader.read_lines
      end

      #
      # Consumes the entire response body and returns it.
      #
      # @return [String]  the response body
      #
      def read_all
        @reader.read_all
      end

      private

      # Build an HTTP request line and headers.
      def build_request(uri, headers)
        ret = "GET #{uri.request_uri} HTTP/1.1\r\n"
        ret << "Host: #{uri.host}\r\n"
        headers.each { |k, v|
          ret << "#{k}: #{v}\r\n"
        }
        ret + "\r\n"
      end
    end

    #
    # Used internally to send the HTTP request, including the proxy dialogue if necessary.
    # @private
    #
    class HTTPConnectionFactory
      def self.connect(uri, proxy, connect_timeout, read_timeout)
        if !proxy
          return open_socket(uri, connect_timeout)
        end

        socket = open_socket(proxy, connect_timeout)
        socket.write(build_proxy_request(uri, proxy))

        # temporarily create a reader just for the proxy connect response
        proxy_reader = HTTPResponseReader.new(socket, read_timeout)
        if proxy_reader.status != 200
          raise Errors::HTTPProxyError.new(proxy_reader.status)
        end

        # start using TLS at this point if appropriate
        if uri.scheme.downcase == 'https'
          wrap_socket_in_ssl_socket(socket)
        else
          socket
        end
      end

      private

      def self.open_socket(uri, connect_timeout)
        if uri.scheme.downcase == 'https'
          Socketry::SSL::Socket.connect(uri.host, uri.port, timeout: connect_timeout)
        else
          Socketry::TCP::Socket.connect(uri.host, uri.port, timeout: connect_timeout)
        end
      end

      # Build a proxy connection header.
      def self.build_proxy_request(uri, proxy)
        ret = "CONNECT #{uri.host}:#{uri.port} HTTP/1.1\r\n"
        ret << "Host: #{uri.host}:#{uri.port}\r\n"
        if proxy.user || proxy.password
          encoded_credentials = Base64.strict_encode64([proxy.user || '', proxy.password || ''].join(":"))
          ret << "Proxy-Authorization: Basic #{encoded_credentials}\r\n"
        end
        ret << "\r\n"
        ret
      end

      def self.wrap_socket_in_ssl_socket(socket)
        io = IO.try_convert(socket)
        ssl_sock = OpenSSL::SSL::SSLSocket.new(io, OpenSSL::SSL::SSLContext.new)
        ssl_sock.connect
        Socketry::SSL::Socket.new.from_socket(ssl_sock)
      end
    end

    #
    # Used internally to read the HTTP response, either all at once or as a stream of text lines.
    # Incoming data is fed into an instance of HTTPTools::Parser, which gives us the header and
    # chunks of the body via callbacks.
    # @private
    #
    class HTTPResponseReader
      DEFAULT_CHUNK_SIZE = 10000

      attr_reader :status, :headers

      def initialize(socket, read_timeout)
        @socket = socket
        @read_timeout = read_timeout
        @parser = HTTPTools::Parser.new
        @buffer = ""
        @done = false
        @lock = Mutex.new

        # Provide callbacks for the Parser to give us the headers and body. This has to be done
        # before we start piping any data into the parser.
        have_headers = false
        @parser.on(:header) do
          have_headers = true
        end
        @parser.on(:stream) do |data|
          @lock.synchronize { @buffer << data }  # synchronize because we're called from another thread in Socketry
        end
        @parser.on(:finish) do
          @lock.synchronize { @done = true }
        end

        # Block until the status code and headers have been successfully read.
        while !have_headers
          raise EOFError if !read_chunk_into_buffer
        end
        @headers = Hash[@parser.header.map { |k,v| [k.downcase, v] }]
        @status = @parser.status_code
      end

      def read_lines
        Enumerator.new do |gen|
          loop do
            line = read_line
            break if line.nil?
            gen.yield line
          end
        end
      end

      def read_all
        while read_chunk_into_buffer
        end
        @buffer
      end

      private

      # Attempt to read some more data from the socket. Return true if successful, false if EOF.
      # A read timeout will result in an exception from Socketry's readpartial method.
      def read_chunk_into_buffer
        # If @done is set, it means the Parser has signaled end of response body
        @lock.synchronize { return false if @done }
        begin
          data = @socket.readpartial(DEFAULT_CHUNK_SIZE, timeout: @read_timeout)
        rescue Socketry::TimeoutError
          # We rethrow this as our own type so the caller doesn't have to know the Socketry API
          raise Errors::ReadTimeoutError.new(@read_timeout)
        end
        return false if data == :eof
        @parser << data
        # We are piping the content through the parser so that it can handle things like chunked
        # encoding for us. The content ends up being appended to @buffer via our callback.
        true
      end

      # Extract the next line of text from the read buffer, refilling the buffer as needed.
      def read_line
        loop do
          @lock.synchronize do
            i = @buffer.index(/[\r\n]/)
            if !i.nil?
              i += 1 if (@buffer[i] == "\r" && i < @buffer.length - 1 && @buffer[i + 1] == "\n")
              return @buffer.slice!(0, i + 1).force_encoding(Encoding::UTF_8)
            end
          end
          return nil if !read_chunk_into_buffer
        end
      end
    end
  end
end
