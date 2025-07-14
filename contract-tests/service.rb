require 'ld-eventsource'
require 'json'
require 'logger'
require 'net/http'
require 'sinatra'

require './stream_entity.rb'

$log = Logger.new(STDOUT)
$log.formatter = proc {|severity, datetime, progname, msg|
  "#{datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')} #{severity} #{progname} #{msg}\n"
}

set :port, 8000
set :logging, false

streams = {}
streamCounter = 0

get '/' do
  {
    capabilities: [
      'headers',
      'last-event-id',
      'read-timeout',
    ],
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
  ) do |client|
    entity = StreamEntity.new(client, tag, callbackUrl)
  end

  streams[streamId] = entity

  return [201, {"Location" => streamResourceUrl}, nil]
end

delete '/streams/:id' do |streamId|
  entity = streams[streamId]
  return 404 if entity.nil?
  streams.delete(streamId)
  entity.close

  return 204
end
