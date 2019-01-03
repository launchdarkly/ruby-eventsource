LaunchDarkly SSE Client for Ruby
================================

[![Gem Version](https://badge.fury.io/rb/ld-eventsource.svg)](http://badge.fury.io/rb/ld-eventsource)

[![Circle CI](https://circleci.com/gh/launchdarkly/ruby-eventsource/tree/master.svg?style=svg)](https://circleci.com/gh/launchdarkly/ruby-eventsource/tree/master)
[![security](https://hakiri.io/github/launchdarkly/ruby-eventsource/master.svg)](https://hakiri.io/github/launchdarkly/ruby-eventsource/master)

A client for the [Server-Sent Events](https://www.w3.org/TR/eventsource/) protocol. This implementation runs on a worker thread, and uses the `[https://rubygems.org/gems/socketry](socketry)` gem to manage a persistent connection. Its primary purpose is to support the [LaunchDarkly SDK for Ruby](https://github.com/launchdarkly/ruby-client), but it can be used independently.

Parts of this code are based on https://github.com/Tonkpils/celluloid-eventsource, but it does not use Celluloid.

Supported Ruby versions
-----------------------

This gem has a minimum Ruby version of 2.2.6, or 9.1.6 for JRuby.

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
sse_client = LaunchDarklySSE::Client.new("http://hostname/resource/path") do |client|
  client.on_event do |event|
    puts "I received an event: #{event.type}, #{event.data}"
  end
end
```

For other options available with the `Client` constructor, see the [API documentation](https://www.rubydoc.info/gems/ld-eventsource).

Contributing
------------

We welcome questions, suggestions, and pull requests at our [Github repository](https://github.com/launchdarkly/ruby-eventsource).

About LaunchDarkly
------------------

* LaunchDarkly is a continuous delivery platform that provides feature flags as a service and allows developers to iterate quickly and safely. We allow you to easily flag your features and manage them from the LaunchDarkly dashboard.  With LaunchDarkly, you can:
    * Roll out a new feature to a subset of your users (like a group of users who opt-in to a beta tester group), gathering feedback and bug reports from real-world use cases.
    * Gradually roll out a feature to an increasing percentage of users, and track the effect that the feature has on key metrics (for instance, how likely is a user to complete a purchase if they have feature A versus feature B?).
    * Turn off a feature that you realize is causing performance problems in production, without needing to re-deploy, or even restart the application with a changed configuration file.
    * Grant access to certain features based on user attributes, like payment plan (eg: users on the ‘gold’ plan get access to more features than users in the ‘silver’ plan). Disable parts of your application to facilitate maintenance, without taking everything offline.
* LaunchDarkly provides feature flag SDKs for
    * [Java](http://docs.launchdarkly.com/docs/java-sdk-reference "Java SDK")
    * [JavaScript](http://docs.launchdarkly.com/docs/js-sdk-reference "LaunchDarkly JavaScript SDK")
    * [PHP](http://docs.launchdarkly.com/docs/php-sdk-reference "LaunchDarkly PHP SDK")
    * [Python](http://docs.launchdarkly.com/docs/python-sdk-reference "LaunchDarkly Python SDK")
    * [Go](http://docs.launchdarkly.com/docs/go-sdk-reference "LaunchDarkly Go SDK")
    * [Node.JS](http://docs.launchdarkly.com/docs/node-sdk-reference "LaunchDarkly Node SDK")
    * [Electron](http://docs.launchdarkly.com/docs/electron-sdk-reference "LaunchDarkly Electron SDK")
    * [.NET](http://docs.launchdarkly.com/docs/dotnet-sdk-reference "LaunchDarkly .Net SDK")
    * [Ruby](http://docs.launchdarkly.com/docs/ruby-sdk-reference "LaunchDarkly Ruby SDK")
    * [iOS](http://docs.launchdarkly.com/docs/ios-sdk-reference "LaunchDarkly iOS SDK")
    * [Android](http://docs.launchdarkly.com/docs/android-sdk-reference "LaunchDarkly Android SDK")
* Explore LaunchDarkly
    * [launchdarkly.com](http://www.launchdarkly.com/ "LaunchDarkly Main Website") for more information
    * [docs.launchdarkly.com](http://docs.launchdarkly.com/  "LaunchDarkly Documentation") for our documentation and SDKs
    * [apidocs.launchdarkly.com](http://apidocs.launchdarkly.com/  "LaunchDarkly API Documentation") for our API documentation
    * [blog.launchdarkly.com](http://blog.launchdarkly.com/  "LaunchDarkly Blog Documentation") for the latest product updates
    * [Feature Flagging Guide](https://github.com/launchdarkly/featureflags/  "Feature Flagging Guide") for best practices and strategies
