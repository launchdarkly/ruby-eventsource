require "ld-eventsource"
require "http_stub"

#
# End-to-end tests of the SSE client against a real server
#
describe SSE::Client do
  before(:each) do
    skip("end-to-end HTTP tests are disabled because they're unreliable on this platform") unless stub_http_server_available?
  end

  subject { SSE::Client }

  let(:simple_event_1) { SSE::StreamEvent.new(:go, "foo")}
  let(:simple_event_2) { SSE::StreamEvent.new(:stop, "bar")}
  let(:simple_event_1_text) { <<-EOT
event: go
data: foo

EOT
  }
  let(:simple_event_2_text) { <<-EOT
event: stop
data: bar

EOT
  }
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

  it "sends expected headers" do
    with_server do |server|
      requests = Queue.new
      server.setup_response("/") do |req,res|
        requests << req
        send_stream_content(res, "", keep_open: true)
      end

      headers = { "Authorization" => "secret" }

      with_client(subject.new(server.base_uri, headers: headers)) do |client|
        received_req = requests.pop
        expect(received_req.header).to eq({
          "accept" => ["text/event-stream"],
          "cache-control" => ["no-cache"],
          "host" => ["127.0.0.1:" + server.port.to_s],
          "authorization" => ["secret"],
          "user-agent" => ["ruby-eventsource"],
          "connection" => ["close"],
        })
      end
    end
  end

  it "sends initial Last-Event-Id if specified" do
    id = "xyz"
    with_server do |server|
      requests = Queue.new
      server.setup_response("/") do |req,res|
        requests << req
        send_stream_content(res, "", keep_open: true)
      end

      headers = { "Authorization" => "secret" }

      with_client(subject.new(server.base_uri, headers: headers, last_event_id: id)) do |client|
        received_req = requests.pop
        expect(received_req.header).to eq({
          "accept" => ["text/event-stream"],
          "cache-control" => ["no-cache"],
          "host" => ["127.0.0.1:" + server.port.to_s],
          "authorization" => ["secret"],
          "last-event-id" => [id],
          "user-agent" => ["ruby-eventsource"],
          "connection" => ["close"],
        })
      end
    end
  end

  it "receives messages" do
    events_body = simple_event_1_text + simple_event_2_text
    with_server do |server|
      server.setup_response("/") do |req,res|
        send_stream_content(res, events_body, keep_open: true)
      end

      event_sink = Queue.new
      client = subject.new(server.base_uri) do |c|
        c.on_event { |event| event_sink << event }
      end

      with_client(client) do |c|
        expect(event_sink.pop).to eq(simple_event_1)
        expect(event_sink.pop).to eq(simple_event_2)
      end
    end
  end

  it "does not trigger an error when stream is closed" do
    events_body = simple_event_1_text + simple_event_2_text
    with_server do |server|
      server.setup_response("/") do |req,res|
        send_stream_content(res, events_body, keep_open: true)
      end

      event_sink = Queue.new
      error_sink = Queue.new
      client = subject.new(server.base_uri) do |c|
        c.on_event { |event| event_sink << event }
        c.on_error { |error| error_sink << error }
      end

      with_client(client) do |c|
        event_sink.pop  # wait till we have definitely started reading the stream
        c.close
        sleep 0.25  # there's no way to really know when the stream thread has finished
        expect(error_sink.empty?).to be true
      end
    end
  end

  it "reconnects after error response" do
    events_body = simple_event_1_text
    with_server do |server|
      attempt = 0
      server.setup_response("/") do |req,res|
        attempt += 1
        if attempt == 1
          res.status = 500
          res.body = "sorry"
          res.keep_alive = false
        else
          send_stream_content(res, events_body, keep_open: true)
        end
      end

      event_sink = Queue.new
      error_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: reconnect_asap) do |c|
        c.on_event { |event| event_sink << event }
        c.on_error { |error| error_sink << error }
      end

      with_client(client) do |c|
        expect(event_sink.pop).to eq(simple_event_1)
        expect(error_sink.pop).to eq(SSE::Errors::HTTPStatusError.new(500, "sorry"))
        expect(attempt).to eq 2
      end
    end
  end

  it "reconnects after invalid content type" do
    events_body = simple_event_1_text
    with_server do |server|
      attempt = 0
      server.setup_response("/") do |req,res|
        attempt += 1
        if attempt == 1
          res.status = 200
          res.content_type = "text/plain"
          res.body = "sorry"
          res.keep_alive = false
        else
          send_stream_content(res, events_body, keep_open: true)
        end
      end

      event_sink = Queue.new
      error_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: reconnect_asap) do |c|
        c.on_event { |event| event_sink << event }
        c.on_error { |error| error_sink << error }
      end

      with_client(client) do |c|
        expect(event_sink.pop).to eq(simple_event_1)
        expect(error_sink.pop).to eq(SSE::Errors::HTTPContentTypeError.new("text/plain"))
        expect(attempt).to eq 2
      end
    end
  end

  it "reconnects after read timeout" do
    events_body = simple_event_1_text
    with_server do |server|
      attempt = 0
      server.setup_response("/") do |req,res|
        attempt += 1
        if attempt == 1
          sleep(1)
        end
        send_stream_content(res, events_body, keep_open: true)
      end

      event_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: reconnect_asap, read_timeout: 0.25) do |c|
        c.on_event { |event| event_sink << event }
      end

      with_client(client) do |c|
        expect(event_sink.pop).to eq(simple_event_1)
        expect(attempt).to eq 2
      end
    end
  end

  it "reconnects if stream returns EOF" do
    with_server do |server|
      attempt = 0
      server.setup_response("/") do |req,res|
        attempt += 1
        send_stream_content(res, attempt == 1 ? simple_event_1_text : simple_event_2_text,
          keep_open: attempt == 2)
      end

      event_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: reconnect_asap) do |c|
        c.on_event { |event| event_sink << event }
      end

      with_client(client) do |c|
        expect(event_sink.pop).to eq(simple_event_1)
        expect(event_sink.pop).to eq(simple_event_2)
        expect(attempt).to eq 2
      end
    end
  end

  it "sends ID of last received event, if any, when reconnecting" do
    with_server do |server|
      requests = Queue.new
      attempt = 0
      server.setup_response("/") do |req,res|
        requests << req
        attempt += 1
        if attempt == 1
          send_stream_content(res, "data: foo\nid: a\n\n", keep_open: false)
        else
          send_stream_content(res, "data: bar\nid: b\n\n", keep_open: true)
        end
      end

      event_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: reconnect_asap) do |c|
        c.on_event { |event| event_sink << event }
      end

      with_client(client) do |c|
        req1 = requests.pop
        req2 = requests.pop
        expect(req2.header["last-event-id"]).to eq([ "a" ])
      end
    end
  end

  it "increases backoff delay if a failure happens within the reset threshold" do
    request_times = []
    max_requests = 5
    initial_interval = 0.25

    with_server do |server|
      attempt = 0
      server.setup_response("/") do |req,res|
        request_times << Time.now
        attempt += 1
        send_stream_content(res, simple_event_1_text, keep_open: attempt == max_requests)
      end

      event_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: initial_interval) do |c|
        c.on_event { |event| event_sink << event }
      end

      with_client(client) do |c|
        last_interval = nil
        max_requests.times do |i|
          expect(event_sink.pop).to eq(simple_event_1)
          if i > 0
            interval = request_times[i] - request_times[i - 1]
            minimum_expected_interval = initial_interval * (2 ** (i - 1)) / 2
            expect(interval).to be >= minimum_expected_interval
            last_interval = interval
          end
        end
      end
    end
  end

  it "resets backoff delay if a failure happens after the reset threshold" do
    request_times = []
    request_end_times = []
    max_requests = 5
    threshold = 0.3
    initial_interval = 0.25

    with_server do |server|
      attempt = 0
      server.setup_response("/") do |req,res|
        request_times << Time.now
        attempt += 1
        stream = send_stream_content(res, simple_event_1_text, keep_open: true)
        Thread.new do
          sleep(threshold + 0.01)
          stream.close
          request_end_times << Time.now
        end
      end

      event_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: initial_interval, reconnect_reset_interval: threshold) do |c|
        c.on_event { |event| event_sink << event }
      end

      with_client(client) do |c|
        last_interval = nil
        max_requests.times do |i|
          expect(event_sink.pop).to eq(simple_event_1)
          if i > 0
            interval = request_times[i] - request_end_times[i - 1]
            expect(interval).to be <= (initial_interval + 0.1)
          end
        end
      end
    end
  end

  it "can change initial reconnect delay based on directive from server" do
    request_times = []
    configured_interval = 1
    retry_ms = 100

    with_server do |server|
      attempt = 0
      server.setup_response("/") do |req,res|
        request_times << Time.now
        attempt += 1
        if attempt == 1
          send_stream_content(res, "retry: #{retry_ms}\n", keep_open: false)
        else
          send_stream_content(res, simple_event_1_text, keep_open: true)
        end
      end

      event_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: configured_interval) do |c|
        c.on_event { |event| event_sink << event }
      end

      with_client(client) do |c|
        expect(event_sink.pop).to eq(simple_event_1)
        interval = request_times[1] - request_times[0]
        expect(interval).to be < 0.5
      end
    end
  end

  it "connects to HTTP server through proxy" do
    events_body = simple_event_1_text
    with_server do |server|
      server.setup_response("/") do |req,res|
        send_stream_content(res, events_body, keep_open: false)
      end
      with_server(StubProxyServer.new) do |proxy|
        event_sink = Queue.new
        client = subject.new(server.base_uri, proxy: proxy.base_uri) do |c|
          c.on_event { |event| event_sink << event }
        end

        with_client(client) do |c|
          expect(event_sink.pop).to eq(simple_event_1)
          expect(proxy.request_count).to eq(1)
        end
      end
    end
  end

  it "resets read timeout between events" do
    event_body = simple_event_1_text
    with_server do |server|
      attempt = 0
      server.setup_response("/") do |req,res|
        attempt += 1
        if attempt == 1
          stream = send_stream_content(res, event_body, keep_open: true)
          Thread.new do
            2.times {
              # write within timeout interval
              sleep(0.75)
              stream.write(event_body)
            }
            # cause timeout
            sleep(1.25)
          end
        elsif attempt == 2
          send_stream_content(res, event_body, keep_open: false)
        end
      end

      event_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: reconnect_asap, read_timeout: 1) do |c|
        c.on_event { |event| event_sink << event }
      end

      with_client(client) do |c|
        4.times {
          expect(event_sink.pop).to eq(simple_event_1)
        }
        expect(attempt).to eq 2
      end
    end
  end

  it "returns true from closed? when closed" do
    with_server do |server|
      server.setup_response("/") do |req,res|
        send_stream_content(res, "", keep_open: true)
      end

      with_client(subject.new(server.base_uri)) do |client|
        expect(client.closed?).to be(false)

        client.close
        expect(client.closed?).to be(true)
      end
    end
  end

  describe "HTTP method parameter" do
    it "defaults to GET method" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        with_client(subject.new(server.base_uri)) do |client|
          received_req = requests.pop
          expect(received_req.request_method).to eq("GET")
        end
      end
    end

    it "uses explicit GET method" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        with_client(subject.new(server.base_uri, method: "GET")) do |client|
          received_req = requests.pop
          expect(received_req.request_method).to eq("GET")
        end
      end
    end

    it "uses explicit POST method" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        with_client(subject.new(server.base_uri, method: "POST")) do |client|
          received_req = requests.pop
          expect(received_req.request_method).to eq("POST")
        end
      end
    end

    it "normalizes method to uppercase" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        with_client(subject.new(server.base_uri, method: "post")) do |client|
          received_req = requests.pop
          expect(received_req.request_method).to eq("POST")
        end
      end
    end
  end

  describe "payload parameter" do
    it "sends string payload as body" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        payload = "test-string-payload"
        with_client(subject.new(server.base_uri, method: "POST", payload: payload)) do |client|
          received_req = requests.pop
          expect(received_req.request_method).to eq("POST")
          expect(received_req.body).to eq(payload)
        end
      end
    end

    it "sends hash payload as JSON" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        payload = {user: "test", id: 123}
        with_client(subject.new(server.base_uri, method: "POST", payload: payload)) do |client|
          received_req = requests.pop
          expect(received_req.request_method).to eq("POST")
          expect(received_req.header["content-type"].first).to include("application/json")
          parsed_body = JSON.parse(received_req.body)
          expect(parsed_body).to eq({"user" => "test", "id" => 123})
        end
      end
    end

    it "sends array payload as JSON" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        payload = ["item1", "item2", "item3"]
        with_client(subject.new(server.base_uri, method: "POST", payload: payload)) do |client|
          received_req = requests.pop
          expect(received_req.request_method).to eq("POST")
          expect(received_req.header["content-type"].first).to include("application/json")
          parsed_body = JSON.parse(received_req.body)
          expect(parsed_body).to eq(["item1", "item2", "item3"])
        end
      end
    end

    it "works with GET method and payload" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        payload = "get-with-payload"
        with_client(subject.new(server.base_uri, method: "GET", payload: payload)) do |client|
          received_req = requests.pop
          expect(received_req.request_method).to eq("GET")
          expect(received_req.body).to eq(payload)
        end
      end
    end
  end

  describe "callable payload parameter" do
    it "invokes lambda payload on each request" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: false)  # Close to trigger reconnect
        end

        counter = 0
        callable_payload = -> { counter += 1; "request-#{counter}" }

        with_client(subject.new(server.base_uri, method: "POST", payload: callable_payload, reconnect_time: reconnect_asap)) do |client|
          # Wait for first request
          req1 = requests.pop
          expect(req1.body).to eq("request-1")

          # Wait for reconnect and second request
          req2 = requests.pop
          expect(req2.body).to eq("request-2")
        end
      end
    end

    it "invokes proc payload on each request" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: false)
        end

        counter = 0
        callable_payload = proc { counter += 1; {request_id: counter, timestamp: Time.now.to_i} }

        with_client(subject.new(server.base_uri, method: "POST", payload: callable_payload, reconnect_time: reconnect_asap)) do |client|
          # Wait for first request
          req1 = requests.pop
          parsed_body1 = JSON.parse(req1.body)
          expect(parsed_body1["request_id"]).to eq(1)

          # Wait for reconnect and second request
          req2 = requests.pop
          parsed_body2 = JSON.parse(req2.body)
          expect(parsed_body2["request_id"]).to eq(2)
          expect(parsed_body2["timestamp"]).to be >= parsed_body1["timestamp"]
        end
      end
    end

    it "invokes custom callable object payload" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        class TestPayloadGenerator
          def initialize
            @counter = 0
          end

          def call
            @counter += 1
            {generator: "test", count: @counter}
          end
        end

        callable_payload = TestPayloadGenerator.new
        with_client(subject.new(server.base_uri, method: "POST", payload: callable_payload)) do |client|
          received_req = requests.pop
          parsed_body = JSON.parse(received_req.body)
          expect(parsed_body).to eq({"generator" => "test", "count" => 1})
        end
      end
    end

    it "handles callable returning string" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        callable_payload = -> { "dynamic-string-#{rand(1000)}" }
        with_client(subject.new(server.base_uri, method: "POST", payload: callable_payload)) do |client|
          received_req = requests.pop
          expect(received_req.body).to match(/^dynamic-string-\d+$/)
        end
      end
    end

    it "handles callable returning hash" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        callable_payload = -> { {type: "dynamic", value: rand(1000)} }
        with_client(subject.new(server.base_uri, method: "POST", payload: callable_payload)) do |client|
          received_req = requests.pop
          expect(received_req.header["content-type"].first).to include("application/json")
          parsed_body = JSON.parse(received_req.body)
          expect(parsed_body["type"]).to eq("dynamic")
          expect(parsed_body["value"]).to be_a(Integer)
        end
      end
    end

    it "handles callable returning array" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        callable_payload = -> { ["dynamic", Time.now.to_i] }
        with_client(subject.new(server.base_uri, method: "POST", payload: callable_payload)) do |client|
          received_req = requests.pop
          expect(received_req.header["content-type"].first).to include("application/json")
          parsed_body = JSON.parse(received_req.body)
          expect(parsed_body[0]).to eq("dynamic")
          expect(parsed_body[1]).to be_a(Integer)
        end
      end
    end

    it "handles callable returning other types by converting to string" do
      with_server do |server|
        requests = Queue.new
        server.setup_response("/") do |req,res|
          requests << req
          send_stream_content(res, "", keep_open: true)
        end

        test_object = Object.new
        def test_object.to_s
          "custom-object-string"
        end

        callable_payload = -> { test_object }
        with_client(subject.new(server.base_uri, method: "POST", payload: callable_payload)) do |client|
          received_req = requests.pop
          expect(received_req.body).to eq("custom-object-string")
        end
      end
    end
  end
end
