require "webrick"
require "webrick/httpproxy"
require "webrick/https"

class StubHTTPServer
  def initialize
    @port = 50000
    begin
      @server = create_server(@port)
    rescue Errno::EADDRINUSE
      @port += 1
      retry
    end
  end

  def create_server(port)
    WEBrick::HTTPServer.new(
      BindAddress: '127.0.0.1',
      Port: port,
      AccessLog: [],
      Logger: NullLogger.new
    )
  end

  def start
    Thread.new { @server.start }
  end

  def stop
    @server.shutdown
  end

  def base_uri
    URI("http://127.0.0.1:#{@port}")
  end

  def setup_response(uri_path, &action)
    @server.mount_proc(uri_path, action)
  end
end

class StubProxyServer < StubHTTPServer
  attr_reader :request_count
  attr_accessor :connect_status

  def initialize
    super
    @request_count = 0
  end

  def create_server(port)
    WEBrick::HTTPProxyServer.new(
      BindAddress: '127.0.0.1',
      Port: port,
      AccessLog: [],
      Logger: NullLogger.new,
      ProxyContentHandler: proc do |req,res|
        if !@connect_status.nil?
          res.status = @connect_status
        end
        @request_count += 1
      end
    )
  end
end

class NullLogger
  def method_missing(*)
    self
  end
end

def with_server(server = nil)
  server = StubHTTPServer.new if server.nil?
  begin
    server.start
    yield server
  ensure
    server.stop
  end
end
