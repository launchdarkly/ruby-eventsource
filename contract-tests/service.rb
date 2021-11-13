require 'ld-eventsource'
require 'json'
require 'logger'
require 'net/http'
require 'sinatra'

$log = Logger.new(STDOUT)
$log.formatter = proc {|severity, datetime, progname, msg|
  "#{datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')} #{severity} #{progname} #{msg}\n"
}

set :port, 8000
set :logging, false

streams = {}
streamCounter = 0

class StreamEntity
  def initialize(sse, tag, callbackUrl)
    @sse = sse
    @tag = tag
    @callbackUrl = callbackUrl

    sse.on_event { |event| self.on_event(event) }
    sse.on_error { |error| self.on_error(error) }
  end

  def on_event(event)
    $log.info("#{@tag} Received event from stream (#{event.type})")
    message = {
      kind: 'event',
      event: {
        type: event.type,
        data: event.data,
        id: event.id
      }
    }
    self.send_message(message)
  end

  def on_error(error)
    $log.info("#{@tag} Received error from stream: #{error}")
    message = {
      kind: 'error',
      error: error
    }
    self.send_message(message)
  end

  def send_message(message)
    resp = Net::HTTP.post(URI(@callbackUrl), JSON.generate(message))
    if resp.code.to_i >= 300
      $log.error("#{@tag} Callback post returned status #{resp.code}")
    end
  end

  def close
    @sse.close
    $log.info("#{@tag} Test ended")
  end
end

get '/' do
  {
    capabilities: [
      'headers',
      'last-event-id',
      'read-timeout'
    ]
  }.to_json
end

delete '/' do
  $log.info("Test service has told us to exit")
  Thread.new { sleep 1; exit }
  return 204
end

post '/' do
  opts = JSON.parse(request.body.read, :symbolize_names => true)
  streamUrl = opts[:streamUrl]
  callbackUrl = opts[:callbackUrl]
  tag = "[#{opts[:tag]}]:"

  if !streamUrl || !callbackUrl
    $log.error("#{tag} Received request with incomplete parameters: #{opts}")
    return 400
  end

  streamCounter += 1
  streamId = streamCounter.to_s
  streamResourceUrl = "/streams/#{streamId}"

  $log.info("#{tag} Starting stream from #{streamUrl}")
  $log.debug("#{tag} Parameters: #{opts}")

  entity = nil
  sse = SSE::Client.new(
    streamUrl,
    headers: opts[:headers] || {},
    last_event_id: opts[:lastEventId],
    read_timeout: opts[:readTimeoutMs].nil? ? nil : (opts[:readTimeoutMs].to_f / 1000),
    reconnect_time: opts[:initialDelayMs].nil? ? nil : (opts[:initialDelayMs].to_f / 1000)
  ) do |sse|
    entity = StreamEntity.new(sse, tag, callbackUrl)
  end

  streams[streamId] = entity

  return [201, {'Location': streamResourceUrl}, nil]
end

delete '/streams/:id' do |streamId|
  entity = streams[streamId]
  return 404 if stream.nil?
  streams.delete(streamId)
  entity.close

  return 204
end
