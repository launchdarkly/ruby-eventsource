require "ld-eventsource/impl/backoff"
require "ld-eventsource/impl/event_parser"
require "ld-eventsource/impl/streaming_http"
require "ld-eventsource/events"
require "ld-eventsource/errors"

require "concurrent/atomics"
require "logger"
require "thread"
require "uri"

module SSE
  #
  # A lightweight SSE client implementation. The client uses a worker thread to read from the
  # streaming HTTP connection. Events are dispatched from the same worker thread.
  #
  # The client will attempt to recover from connection failures as follows:
  #
  # * The first time the connection is dropped, it will wait about one second (or whatever value is
  # specified for `reconnect_time`) before attempting to reconnect. The actual delay has a
  # pseudo-random jitter value added.
  # * If the connection fails again within the time range specified by `reconnect_reset_interval`,
  # it will exponentially increase the delay between attempts (and also apply a random jitter).
  # However, if the connection stays up for at least that amount of time, the delay will be reset
  # to the minimum.
  # * Each time a new connection is made, the client will send a `Last-Event-Id` header so the server
  # can pick up where it left off (if the server has been sending ID values for events).
  #
  # It is also possible to force the connection to be restarted if the server sends no data within an
  # interval specified by `read_timeout`. Using a read timeout is advisable because otherwise it is
  # possible in some circumstances for a connection failure to go undetected. To keep the connection
  # from timing out if there are no events to send, the server could send a comment line (`":"`) at
  # regular intervals as a heartbeat.
  #
  class Client
    # The default value for `connect_timeout` in {#initialize}.
    DEFAULT_CONNECT_TIMEOUT = 10

    # The default value for `read_timeout` in {#initialize}.
    DEFAULT_READ_TIMEOUT = 300

    # The default value for `reconnect_time` in {#initialize}.
    DEFAULT_RECONNECT_TIME = 1

    # The maximum number of seconds that the client will wait before reconnecting.
    MAX_RECONNECT_TIME = 30

    # The default value for `reconnect_reset_interval` in {#initialize}.
    DEFAULT_RECONNECT_RESET_INTERVAL = 60

    #
    # Creates a new SSE client.
    #
    # Once the client is created, it immediately attempts to open the SSE connection. You will
    # normally want to register your event handler before this happens, so that no events are missed.
    # To do this, provide a block after the constructor; the block will be executed before opening
    # the connection.
    #
    # @example Specifying an event handler at initialization time
    #     client = SSE::Client.new(uri) do |c|
    #       c.on_event do |event|
    #         puts "I got an event: #{event.type}, #{event.data}"
    #       end
    #     end
    #
    # @param uri [String] the URI to connect to
    # @param headers [Hash] ({})  custom headers to send with each HTTP request
    # @param connect_timeout [Float] (DEFAULT_CONNECT_TIMEOUT)  maximum time to wait for a
    #   connection, in seconds
    # @param read_timeout [Float] (DEFAULT_READ_TIMEOUT)  the connection will be dropped and
    #   restarted if this number of seconds elapse with no data; nil for no timeout
    # @param reconnect_time [Float] (DEFAULT_RECONNECT_TIME)  the initial delay before reconnecting
    #   after a failure, in seconds; this can increase as described in {Client}
    # @param reconnect_reset_interval [Float] (DEFAULT_RECONNECT_RESET_INTERVAL)  if a connection
    #   stays alive for at least this number of seconds, the reconnect interval will return to the
    #   initial value
    # @param last_event_id [String] (nil)  the initial value that the client should send in the
    #   `Last-Event-Id` header, if any
    # @param proxy [String] (nil)  optional URI of a proxy server to use (you can also specify a
    #   proxy with the `HTTP_PROXY` or `HTTPS_PROXY` environment variable)
    # @param logger [Logger]  a Logger instance for the client to use for diagnostic output;
    #   defaults to a logger with WARN level that goes to standard output
    # @yieldparam [Client] client  the new client instance, before opening the connection
    # 
    def initialize(uri,
          headers: {},
          connect_timeout: DEFAULT_CONNECT_TIMEOUT,
          read_timeout: DEFAULT_READ_TIMEOUT,
          reconnect_time: DEFAULT_RECONNECT_TIME,
          reconnect_reset_interval: DEFAULT_RECONNECT_RESET_INTERVAL,
          last_event_id: nil,
          proxy: nil,
          logger: nil)
      @uri = URI(uri)
      @stopped = Concurrent::AtomicBoolean.new(false)

      @headers = headers.clone
      @connect_timeout = connect_timeout
      @read_timeout = read_timeout
      @logger = logger || default_logger

      if proxy
        @proxy = proxy
      else
        proxy_uri = @uri.find_proxy
        if !proxy_uri.nil? && (proxy_uri.scheme == 'http' || proxy_uri.scheme == 'https')
          @proxy = proxy_uri
        end
      end

      @backoff = Impl::Backoff.new(reconnect_time || DEFAULT_RECONNECT_TIME, MAX_RECONNECT_TIME,
        reconnect_reset_interval: reconnect_reset_interval)

      @on = { event: ->(_) {}, error: ->(_) {} }
      @last_id = last_event_id

      yield self if block_given?

      Thread.new do
        run_stream
      end
    end

    #
    # Specifies a block or Proc to receive events from the stream. This will be called once for every
    # valid event received, with a single parameter of type {StreamEvent}. It is called from the same
    # worker thread that reads the stream, so no more events will be dispatched until it returns.
    #
    # Any exception that propagates out of the handler will cause the stream to disconnect and
    # reconnect, on the assumption that data may have been lost and that restarting the stream will
    # cause it to be resent.
    #
    # Any previously specified event handler will be replaced.
    #
    # @yieldparam event [StreamEvent]
    #
    def on_event(&action)
      @on[:event] = action
    end

    #
    # Specifies a block or Proc to receive connection errors. This will be called with a single
    # parameter that is an instance of some exception class-- normally, either some I/O exception or
    # one of the classes in {SSE::Errors}. It is called from the same worker thread that
    # reads the stream, so no more events or errors will be dispatched until it returns.
    #
    # If the error handler decides that this type of error is not recoverable, it has the ability
    # to prevent any further reconnect attempts by calling {Client#close} on the Client. For instance,
    # you might want to do this if the server returned a `401 Unauthorized` error and no other authorization
    # credentials are available, since any further requests would presumably also receive a 401.
    #
    # Any previously specified error handler will be replaced.
    #
    # @yieldparam error [StandardError]
    #
    def on_error(&action)
      @on[:error] = action
    end

    #
    # Permanently shuts down the client and its connection. No further events will be dispatched. This
    # has no effect if called a second time.
    #
    def close
      if @stopped.make_true
        @cxn.close if !@cxn.nil?
        @cxn = nil
      end
    end

    private

    def default_logger
      log = ::Logger.new($stdout)
      log.level = ::Logger::WARN
      log.progname  = 'ld-eventsource'
      log
    end

    def run_stream
      while !@stopped.value
        @cxn = nil
        begin
          @cxn = connect
          # There's a potential race if close was called in the middle of the previous line, i.e. after we
          # connected but before @cxn was set. Checking the variable again is a bit clunky but avoids that.
          return if @stopped.value
          read_stream(@cxn) if !@cxn.nil?
        rescue Errno::EBADF
          # Don't log this as an error - it probably means we closed our own connection deliberately
          @logger.info { "Stream connection closed" }
        rescue StandardError => e
          # This should not be possible because connect catches all StandardErrors
          log_and_dispatch_error(e, "Unexpected error from event source")
        end
        begin
          @cxn.close if !@cxn.nil?
        rescue StandardError => e
          log_and_dispatch_error(e, "Unexpected error while closing stream")
        end
      end
    end

    # Try to establish a streaming connection. Returns the StreamingHTTPConnection object if successful.
    def connect
      loop do
        return if @stopped.value
        interval = @backoff.next_interval
        if interval > 0
          @logger.info { "Will retry connection after #{'%.3f' % interval} seconds" } 
          sleep(interval)
        end
        begin
          @logger.info { "Connecting to event stream at #{@uri}" }
          cxn = Impl::StreamingHTTPConnection.new(@uri,
            proxy: @proxy,
            headers: build_headers,
            connect_timeout: @connect_timeout,
            read_timeout: @read_timeout
          )
          if cxn.status == 200
            content_type = cxn.headers["content-type"]
            if content_type && content_type.start_with?("text/event-stream")
              return cxn  # we're good to proceed
            else
              cxn.close
              err = Errors::HTTPContentTypeError.new(cxn.headers["content-type"])
              @on[:error].call(err)
              @logger.warn { "Event source returned unexpected content type '#{cxn.headers["content-type"]}'" }
            end
          else
            body = cxn.read_all  # grab the whole response body in case it has error details
            cxn.close
            @logger.info { "Server returned error status #{cxn.status}" }
            err = Errors::HTTPStatusError.new(cxn.status, body)
            @on[:error].call(err)
          end
        rescue Errno::EBADF
          raise # See EBADF comment in run_stream
        rescue StandardError => e
          cxn.close if !cxn.nil?
          log_and_dispatch_error(e, "Unexpected error from event source")
        end
        # if unsuccessful, continue the loop to connect again
      end
    end

    # Pipe the output of the StreamingHTTPConnection into the EventParser, and dispatch events as
    # they arrive.
    def read_stream(cxn)
      # Tell the Backoff object that the connection is now in a valid state. It uses that information so
      # it can automatically reset itself if enough time passes between failures.
      @backoff.mark_success

      event_parser = Impl::EventParser.new(cxn.read_lines)
      event_parser.items.each do |item|
        return if @stopped.value
        case item
          when StreamEvent
            dispatch_event(item)
          when Impl::SetRetryInterval
            @logger.debug { "Received 'retry:' directive, setting interval to #{item.milliseconds}ms" }
            @backoff.base_interval = item.milliseconds.to_f / 1000
        end
      end
    end

    def dispatch_event(event)
      @logger.debug { "Received event: #{event}" }
      @last_id = event.id

      # Pass the event to the caller
      @on[:event].call(event)
    end

    def log_and_dispatch_error(e, message)
      @logger.warn { "#{message}: #{e.inspect}"}
      @logger.debug { "Exception trace: #{e.backtrace}" }
      begin
        @on[:error].call(e)      
      rescue StandardError => ee
        @logger.warn { "Error handler threw an exception: #{ee.inspect}"}
        @logger.debug { "Exception trace: #{ee.backtrace}" }
      end
    end

    def build_headers
      h = {
        'Accept' => 'text/event-stream',
        'Cache-Control' => 'no-cache'
      }
      h['Last-Event-Id'] = @last_id if !@last_id.nil?
      h.merge(@headers)
    end
  end
end
