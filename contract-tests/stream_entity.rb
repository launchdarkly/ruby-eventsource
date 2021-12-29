require 'ld-eventsource'
require 'json'
require 'net/http'

set :port, 8000
set :logging, false

streams = {}
streamCounter = 0

class StreamEntity
  def initialize(sse, tag, callbackUrl)
    @sse = sse
    @tag = tag
    @callbackUrl = callbackUrl
    @callbackCounter = 0

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
        id: event.last_event_id
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
    @callbackCounter += 1
    uri = "#{@callbackUrl}/#{@callbackCounter}"
    begin
      resp = Net::HTTP.post(URI(uri), JSON.generate(message))
      if resp.code.to_i >= 300
        $log.error("#{@tag} Callback to #{url} returned status #{resp.code}")
      end
    rescue => e
      $log.error("#{@tag} Callback to #{url} failed: #{e}")
    end
  end

  def close
    @sse.close
    $log.info("#{@tag} Test ended")
  end
end
