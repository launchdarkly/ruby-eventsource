LaunchDarkly SSE Client for Ruby
================================

[![Gem Version](https://badge.fury.io/rb/ld-eventsource.svg)](http://badge.fury.io/rb/ld-eventsource) [![Circle CI](https://circleci.com/gh/launchdarkly/ruby-eventsource/tree/master.svg?style=svg)](https://circleci.com/gh/launchdarkly/ruby-eventsource/tree/master)

A client for the [Server-Sent Events](https://www.w3.org/TR/eventsource/) protocol. This implementation runs on a worker thread, and uses the [`http`](https://rubygems.org/gems/http) gem to manage a persistent connection. Its primary purpose is to support the [LaunchDarkly SDK for Ruby](https://github.com/launchdarkly/ruby-client), but it can be used independently.

Parts of this code are based on https://github.com/Tonkpils/celluloid-eventsource, but it does not use Celluloid.

Supported Ruby versions
-----------------------

This gem has a minimum Ruby version of 2.5, or 9.2 for JRuby.

Quick setup
-----------

1. Install the Ruby SDK with `gem`:

```shell
gem install ld-eventsource
```

2. Import the code:

```ruby
require 'ld-eventsource'
```

3. Create a new SSE client instance and register your event handler:

```ruby
sse_client = SSE::Client.new("http://hostname/resource/path") do |client|
  client.on_event do |event|
    puts "I received an event: #{event.type}, #{event.data}"
  end
end
```

For other options available with the `Client` constructor, see the [API documentation](https://www.rubydoc.info/gems/ld-eventsource).

Contributing
------------

We welcome questions, suggestions, and pull requests at our [Github repository](https://github.com/launchdarkly/ruby-eventsource). Pull requests should be done from a fork.
