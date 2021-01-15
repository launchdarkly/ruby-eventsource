require "ld-eventsource"

#
# End-to-end tests of the SSE client against a real server
#
describe SSE::Client do
  subject { SSE::Client }

  let(:simple_event_1) { SSE::StreamEvent.new(:go, "foo", "a")}
  let(:simple_event_2) { SSE::StreamEvent.new(:stop, "bar", "b")}
  let(:simple_event_1_text) { <<-EOT
event: go
data: foo
id: a

EOT
  }
  let(:simple_event_2_text) { <<-EOT
event: stop
data: bar
id: b

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
    rd, wr = IO.pipe
    wr.write(content)
    res.body = rd
    if !keep_open
      wr.close
    end
    wr
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
          "content-length" => ["0"],
          "connection" => ["close"]
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
          "content-length" => ["0"],
          "connection" => ["close"]
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

      with_client(client) do |client|
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

      with_client(client) do |client|
        event_sink.pop  # wait till we have definitely started reading the stream
        client.close
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

      with_client(client) do |client|
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

      with_client(client) do |client|
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

      with_client(client) do |client|
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

      with_client(client) do |client|
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
        send_stream_content(res, attempt == 1 ? simple_event_1_text : simple_event_2_text,
          keep_open: attempt == 2)
      end

      event_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: reconnect_asap) do |c|
        c.on_event { |event| event_sink << event }
      end

      with_client(client) do |client|
        req1 = requests.pop
        req2 = requests.pop
        expect(req2.header["last-event-id"]).to eq([ simple_event_1.id ])
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

      with_client(client) do |client|
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

      with_client(client) do |client|
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

      with_client(client) do |client|
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

        with_client(client) do |client|
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
            stream.close
          end
        elsif attempt == 2
          send_stream_content(res, event_body, keep_open: false)
        end
      end

      event_sink = Queue.new
      client = subject.new(server.base_uri, reconnect_time: reconnect_asap, read_timeout: 1) do |c|
        c.on_event { |event| event_sink << event }
      end

      with_client(client) do |client|
        4.times {
          expect(event_sink.pop).to eq(simple_event_1)
        }
        expect(attempt).to eq 2
      end
    end
  end
end
