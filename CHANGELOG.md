# Change log

All notable changes to the LaunchDarkly SSE Client for Ruby will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org).

## [2.2.5](https://github.com/launchdarkly/ruby-eventsource/compare/2.2.4...2.2.5) (2025-07-14)


### Bug Fixes

* Bump minimum to ruby 3.1 ([#57](https://github.com/launchdarkly/ruby-eventsource/issues/57)) ([93a9947](https://github.com/launchdarkly/ruby-eventsource/commit/93a994783aa3aa922a213670a3c6183206d8bd8d))
* Explicitly mark buffer variable as unfrozen ([#59](https://github.com/launchdarkly/ruby-eventsource/issues/59)) ([ccf79af](https://github.com/launchdarkly/ruby-eventsource/commit/ccf79af7a541c976298231b7a34c5f5bd0bd8fff))

## [2.2.4](https://github.com/launchdarkly/ruby-eventsource/compare/2.2.3...2.2.4) (2025-04-18)


### Bug Fixes

* Remove rake dependency from gemspec ([#53](https://github.com/launchdarkly/ruby-eventsource/issues/53)) ([8be0ccc](https://github.com/launchdarkly/ruby-eventsource/commit/8be0ccc1572aa6600e03833ac3d37a231b4c14f9))

## [2.2.3](https://github.com/launchdarkly/ruby-eventsource/compare/2.2.2...2.2.3) (2025-03-07)


### Bug Fixes

* Provide thread name for inspection ([#46](https://github.com/launchdarkly/ruby-eventsource/issues/46)) ([191fd68](https://github.com/launchdarkly/ruby-eventsource/commit/191fd68f539447fda22c4cbcdfe575984658780a))

## [2.2.2] - 2023-03-13
### Fixed:
- Content-Type checking was failing in some environments due to casing issues. Updated check to use a more robust header retrieval method. (Thanks, [matt-dutchie](https://github.com/launchdarkly/ruby-eventsource/pull/36)!)

## [2.2.1] - 2022-06-15
### Fixed:
- Improved efficiency of SSE parsing to reduce transient memory/CPU usage spikes when streams contain long lines. (Thanks, [sq-square](https://github.com/launchdarkly/ruby-eventsource/pull/32)!)

## [2.2.0] - 2021-12-31
### Added:
- The `StreamEvent` type now has a new property, `last_event_id`. Unlike the `id` property which reports only the value of the `id:` field (if any) in that particular event, `last_event_id` reports the `id:` value that was most recently specified in _any_ event. The specification states that this state should be included in every event; the ability to distinguish `last_event_id` from `id` is an extended feature of this gem.

### Fixed:
- The client could stop reading the stream and return an error if there was a multi-byte UTF-8 character whose bytes were split across two reads. It now handles this correctly.
- In JRuby only, the client returned an error when trying to reconnect a stream if the initial reconnect delay was set to zero.
- As per the specification, the parser now ignores any `id:` field whose value contains a null (zero byte).
- The last event ID that is sent in the `Last-Event-Id` header was only being updated if an event specified a _non-empty_ value for `id:`. As per the specification, it should be possible to explicitly clear this value by putting an empty `id:` field in an event.

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
