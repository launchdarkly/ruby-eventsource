require "ld-eventsource"

url = "http://localhost:4001"

log = ::Logger.new($stdout)
log.level = ::Logger::DEBUG

while true
    client = SSE::Client.new(url, { logger: log }) do |c|
        c.on_event { |event| puts("event: #{event}") }
        c.on_error { |error| puts("error: #{error}") }
    end
    while true
	    sleep 2
	end
end
