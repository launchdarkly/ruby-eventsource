require 'ld-eventsource'
require 'json'
require 'logger'
require 'sinatra'

log = Logger.new(STDOUT)
log.formatter = proc {|severity, datetime, progname, msg|
  "#{datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')} #{severity} #{progname} #{msg}\n"
}

set :port, 8000

get '/' do
  {
    capabilities: [
      'headers',
      'last-event-id',
      'read-timeout'
    ]
  }.to_json
end

post '/' do
  opts = JSON.parse(request.body.read, :symbolize_names => true)
  url = opts[:url]
  tag = "[#{opts[:tag]}]:"

  headers "Transfer-Encoding" => "chunked"

  log.info("#{tag} Starting stream to #{url}")
  stream do |out|
    sse = SSE::Client.new(
      url,
      headers: opts[:headers] || {},
      last_event_id: opts[:lastEventId],
      read_timeout: opts[:readTimeoutMs].nil? ? nil : (opts[:readTimeoutMs] / 1000),
      reconnect_time: opts[:initialDelayMs].nil? ? nil : (opts[:initialDelayMs] / 1000)
    ) do |sse|
      sse.on_event { |event|
        log.info("#{tag} Received event from stream (#{event.type})")
        message = {
          kind: 'event',
          event: {
            type: event.type,
            data: event.data,
            id: event.id
          }
        }
        send_message(out, message)
      }
      sse.on_error { |error|
        log.info("#{tag} Received error from stream: #{error}")
        message = {
          kind: 'error',
          error: error
        }
        send_message(out, message)
      }
    end
    send_message(out, { kind: 'hello' })
    while true
      if out.closed?
        break
      end
      sleep 0.1      
    end
    sse.close
    log.info("#{tag} Test ended")
  end
end

def send_message(out, message)
  data = JSON.generate(message) + "\n"
  send_chunk(out, data)
end

def send_chunk(out, chunk)
  # The webapp framework is supposed to handle chunked encoding transparently, but at
  # the moment that's not working so we're doing it ourselves
  out << chunk.bytesize.to_s(16) << "\r\n"
  out << chunk << "\r\n"
end
