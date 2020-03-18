# Change log

All notable changes to the LaunchDarkly SSE Client for Ruby will be documented in this file. This project adheres to [Semantic Versioning](http://semver.org).

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
