# Change log

All notable changes to the LaunchDarkly SSE Client for Ruby will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org).

## [2.1.1] - 2021-10-12
### Fixed:
- Performance should now be greatly improved when parsing events that have very long data. Previously, the logic for parsing the stream to find line breaks could result in unnecessary extra scans of the same characters and unnecessary extra string slicing. ([#20](https://github.com/launchdarkly/ruby-eventsource/issues/20))
- The backoff delay algorithm was being inappropriately applied _before_ the first connection attempt. In the default configuration, that meant an extra delay of between 0.5 seconds and 1 second.
- Leading linefeeds were being dropped from multi-line event data. This does not affect use of `SSE::Client` within the LaunchDarkly SDK, because LaunchDarkly streams consist of JSON data so unescaped linefeeds are not significant, but it could affect uses of this library outside of the SDK.

## [2.1.0] - 2021-08-11
### Added:
- New `closed?` method tests whether `close` has been called on the client. (Thanks, [qcn](https://github.com/launchdarkly/ruby-eventsource/pull/13)!)

## [2.0.1] - 2021-08-10
### Changed:
- The dependency version constraint for the `http` gem is now looser: it allows 5.x versions as well as 4.x. The breaking changes in `http` v5.0.0 do not affect `ld-eventsource`.
- The project&#39;s build now uses v2.2.10 of `bundler` due to known vulnerabilities in other versions.
- `Gemfile.lock` has been removed from source control. As this is a library project, the lockfile never affected application code that used this gem, but only affected the gem&#39;s own CI build. It is preferable for the CI build to refer only to the gemspec so that it resolves dependencies the same way an application using this gem would, rather than using pinned dependencies that an application would not use.

## [2.0.0] - 2021-01-26
### Added:
- Added a `socket_factory` configuration option which can be used for socket creation by the HTTP client if provided. The value of `socket_factory` must be an object providing an `open(uri, timeout)` method and returning a connected socket.

### Changed:
- Switched to the `http` gem instead of `socketry` and a custom HTTP client.
- Dropped support for Ruby &lt; version 2.5
- Dropped support for JRuby &lt; version 9.2

## [1.0.3] - 2020-03-17
### Fixed:
- The backoff delay logic for reconnecting after a stream failure was broken so that if a failure occurred after a stream had been active for at least `reconnect_reset_interval` (default 60 seconds), retries would use _no_ delay, potentially causing a flood of requests and a spike in CPU usage.

## [1.0.2] - 2020-03-10
### Removed:
- Removed an unused dependency on `rake`. There are no other changes in this release.


## [1.0.1] - 2019-07-10
### Fixed:
- Calling `close` on the client could cause a misleading warning message in the log, such as `Unexpected error from event source: #<IOError: stream closed in another thread>`.

## [1.0.0] - 2019-01-03

Initial release.
