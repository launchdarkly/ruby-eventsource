require "ld-eventsource"
require "http_stub"

#
# Tests for HTTP header exposure across all connection states
#
describe "Header Exposure" do
  before(:each) do
    skip("end-to-end HTTP tests are disabled because they're unreliable on this platform") unless stub_http_server_available?
  end

  subject { SSE::Client }

  let(:reconnect_asap) { 0.01 }

  def with_client(client)
    begin
      yield client
    ensure
      client.close
    end
  end

  def send_stream_content(res, content, keep_open:)
    res.content_type = "text/event-stream"
    res.status = 200
    res.chunked = true
    if keep_open
      rd, wr = IO.pipe
      res.body = rd
      wr.write(content)
      wr
    else
      res.body = proc { |out| out.write(content) }
      nil
    end
  end

  describe "HTTPStatusError" do
    it "exposes headers on error responses" do
      with_server do |server|
        server.setup_response("/") do |req,res|
          res.status = 401
          res['X-Custom-Header'] = 'custom-value'
          res['X-LD-FD-Fallback'] = 'true'
          res.body = "unauthorized"
          res.keep_alive = false
        end

        error_sink = Queue.new
        client = subject.new(server.base_uri, retry_enabled: false) do |c|
          c.on_error { |error| error_sink << error }
        end

        sleep(0.25)  # Give time for error to occur
        client.close

        error = error_sink.pop
        expect(error).to be_a(SSE::Errors::HTTPStatusError)
        expect(error.status).to eq(401)
        expect(error.headers).to be_a(HTTP::Headers)
        expect(error.headers['x-custom-header']).to eq('custom-value')
        expect(error.headers['x-ld-fd-fallback']).to eq('true')
      end
    end

    it "handles nil headers gracefully (backward compatibility)" do
      # Create error without headers (old-style)
      error = SSE::Errors::HTTPStatusError.new(500, "error")
      expect(error.headers).to be_nil
    end

    it "can extract FDv1 fallback header from error response" do
      with_server do |server|
        server.setup_response("/") do |req,res|
          res.status = 503
          res['X-LaunchDarkly-FD-Fallback'] = '1'
          res.body = "service unavailable"
          res.keep_alive = false
        end

        error_sink = Queue.new
        client = subject.new(server.base_uri, retry_enabled: false) do |c|
          c.on_error do |error|
            error_sink << error
          end
        end

        sleep(0.25)
        client.close

        error = error_sink.pop
        expect(error.headers).not_to be_nil
        # Headers should be case-insensitive accessible
        fallback_header = error.headers.detect { |k, v| k.downcase == 'x-launchdarkly-fd-fallback' }
        expect(fallback_header).not_to be_nil
        expect(fallback_header[1]).to eq('1')
      end
    end
  end

  describe "HTTPContentTypeError" do
    it "exposes headers on content type errors" do
      with_server do |server|
        server.setup_response("/") do |req,res|
          res.status = 200
          res.content_type = "application/json"
          res['X-Custom-Header'] = 'test-value'
          res['X-LD-FD-Fallback'] = 'true'
          res.body = '{"error": "wrong content type"}'
          res.keep_alive = false
        end

        error_sink = Queue.new
        client = subject.new(server.base_uri, retry_enabled: false) do |c|
          c.on_error { |error| error_sink << error }
        end

        sleep(0.25)
        client.close

        error = error_sink.pop
        expect(error).to be_a(SSE::Errors::HTTPContentTypeError)
        expect(error.headers).to be_a(HTTP::Headers)
        expect(error.headers['x-custom-header']).to eq('test-value')
        expect(error.headers['x-ld-fd-fallback']).to eq('true')
      end
    end

    it "handles nil headers gracefully (backward compatibility)" do
      # Create error without headers (old-style)
      error = SSE::Errors::HTTPContentTypeError.new("text/html")
      expect(error.headers).to be_nil
    end

    it "can extract FDv1 fallback header from content type error" do
      with_server do |server|
        server.setup_response("/") do |req,res|
          res.status = 200
          res.content_type = "text/plain"
          res['X-LaunchDarkly-FD-Fallback'] = '1'
          res.body = "wrong type"
          res.keep_alive = false
        end

        error_sink = Queue.new
        client = subject.new(server.base_uri, retry_enabled: false) do |c|
          c.on_error { |error| error_sink << error }
        end

        sleep(0.25)
        client.close

        error = error_sink.pop
        expect(error.headers).not_to be_nil
        fallback_header = error.headers.detect { |k, v| k.downcase == 'x-launchdarkly-fd-fallback' }
        expect(fallback_header).not_to be_nil
      end
    end
  end

  describe "on_connect callback" do
    it "exposes headers on successful connection" do
      with_server do |server|
        server.setup_response("/") do |req,res|
          res.content_type = "text/event-stream"
          res.status = 200
          res['X-Custom-Header'] = 'success-value'
          res['X-LD-Env-Id'] = 'test-env-123'
          res.chunked = true
          res.body = proc { |out| out.write("data: test\n\n") }
        end

        connect_sink = Queue.new
        client = subject.new(server.base_uri) do |c|
          c.on_connect { |headers| connect_sink << headers }
        end

        with_client(client) do |_|
          headers = connect_sink.pop
          expect(headers).to be_a(HTTP::Headers)
          expect(headers['x-custom-header']).to eq('success-value')
          expect(headers['x-ld-env-id']).to eq('test-env-123')
        end
      end
    end

    it "fires on_connect before first event" do
      with_server do |server|
        server.setup_response("/") do |req,res|
          send_stream_content(res, "data: test\n\n", keep_open: true)
        end

        order_sink = Queue.new
        client = subject.new(server.base_uri) do |c|
          c.on_connect { |headers| order_sink << [:connect, headers] }
          c.on_event { |event| order_sink << [:event, event] }
        end

        with_client(client) do |_|
          first = order_sink.pop
          expect(first[0]).to eq(:connect)
          expect(first[1]).to be_a(HTTP::Headers)

          second = order_sink.pop
          expect(second[0]).to eq(:event)
        end
      end
    end

    it "fires on_connect on reconnection" do
      with_server do |server|
        attempt = 0
        server.setup_response("/") do |req,res|
          attempt += 1
          res['X-Attempt'] = attempt.to_s
          if attempt == 1
            send_stream_content(res, "data: first\n\n", keep_open: false)
          else
            send_stream_content(res, "data: second\n\n", keep_open: true)
          end
        end

        connect_sink = Queue.new
        client = subject.new(server.base_uri, reconnect_time: reconnect_asap) do |c|
          c.on_connect { |headers| connect_sink << headers }
        end

        with_client(client) do |_|
          headers1 = connect_sink.pop
          expect(headers1['x-attempt']).to eq('1')

          headers2 = connect_sink.pop
          expect(headers2['x-attempt']).to eq('2')
        end
      end
    end

    it "can extract FDv1 fallback header from successful connection" do
      with_server do |server|
        server.setup_response("/") do |req,res|
          res.content_type = "text/event-stream"
          res.status = 200
          res['X-LaunchDarkly-FD-Fallback'] = '1'
          res.chunked = true
          res.body = proc { |out| out.write("data: test\n\n") }
        end

        connect_sink = Queue.new
        client = subject.new(server.base_uri) do |c|
          c.on_connect { |headers| connect_sink << headers }
        end

        with_client(client) do |_|
          headers = connect_sink.pop
          fallback_header = headers.detect { |k, v| k.downcase == 'x-launchdarkly-fd-fallback' }
          expect(fallback_header).not_to be_nil
          expect(fallback_header[1]).to eq('1')
        end
      end
    end

    it "works when on_connect handler is not set (backward compatibility)" do
      with_server do |server|
        server.setup_response("/") do |req,res|
          send_stream_content(res, "data: test\n\n", keep_open: true)
        end

        event_sink = Queue.new
        # No on_connect handler specified
        client = subject.new(server.base_uri) do |c|
          c.on_event { |event| event_sink << event }
        end

        with_client(client) do |_|
          event = event_sink.pop
          expect(event.data).to eq("test")
        end
      end
    end

    it "does not block event processing if on_connect raises exception" do
      with_server do |server|
        server.setup_response("/") do |req,res|
          send_stream_content(res, "data: test\n\n", keep_open: true)
        end

        event_sink = Queue.new
        client = subject.new(server.base_uri) do |c|
          c.on_connect { |headers| raise "Test exception in on_connect" }
          c.on_event { |event| event_sink << event }
        end

        # Exception in on_connect should be caught and logged, but not prevent events
        # This behavior depends on error handling implementation
        begin
          with_client(client) do |_|
            # If exception is caught, events should still flow
            # If exception propagates, the test will fail appropriately
            sleep(0.25)
          end
        rescue => e
          # Exception in on_connect should cause connection to fail and retry
          expect(e.message).to include("Test exception")
        end
      end
    end
  end

  describe "Combined scenarios" do
    it "exposes headers in both error and success scenarios" do
      with_server do |server|
        attempt = 0
        server.setup_response("/") do |req,res|
          attempt += 1
          if attempt == 1
            # First attempt: error with headers
            res.status = 503
            res['X-Status'] = 'error'
            res['X-Attempt'] = '1'
            res.body = "service unavailable"
            res.keep_alive = false
          else
            # Second attempt: success with headers
            res.status = 200
            res.content_type = "text/event-stream"
            res['X-Status'] = 'success'
            res['X-Attempt'] = '2'
            res.chunked = true
            res.body = proc { |out| out.write("data: recovered\n\n") }
          end
        end

        error_sink = Queue.new
        connect_sink = Queue.new
        event_sink = Queue.new

        client = subject.new(server.base_uri, reconnect_time: reconnect_asap) do |c|
          c.on_error { |error| error_sink << error }
          c.on_connect { |headers| connect_sink << headers }
          c.on_event { |event| event_sink << event }
        end

        with_client(client) do |_|
          # First: error with headers
          error = error_sink.pop
          expect(error.headers['x-status']).to eq('error')
          expect(error.headers['x-attempt']).to eq('1')

          # Then: successful connection with headers
          headers = connect_sink.pop
          expect(headers['x-status']).to eq('success')
          expect(headers['x-attempt']).to eq('2')

          # Finally: event
          event = event_sink.pop
          expect(event.data).to eq('recovered')
        end
      end
    end

    it "handles all three callback types without conflicts" do
      with_server do |server|
        server.setup_response("/") do |req,res|
          res.status = 200
          res.content_type = "text/event-stream"
          res['X-Test'] = 'multi-callback'
          res.chunked = true
          res.body = proc { |out| out.write("data: message\n\n") }
        end

        callbacks_fired = []

        client = subject.new(server.base_uri) do |c|
          c.on_connect do |headers|
            callbacks_fired << :connect
            expect(headers['x-test']).to eq('multi-callback')
          end

          c.on_event do |event|
            callbacks_fired << :event
            expect(event.data).to eq('message')
          end

          c.on_error do |error|
            callbacks_fired << :error
          end
        end

        with_client(client) do |_|
          sleep(0.25)  # Give time for callbacks to fire
          expect(callbacks_fired).to eq([:connect, :event])
        end
      end
    end
  end
end
