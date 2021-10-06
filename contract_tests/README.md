# SSE client contract test service

This directory contains an implementation of the cross-platform SSE testing protocol defined by https://github.com/launchdarkly/sse-contract-testing. See that project's `README` for details of this protocol, and the kinds of SSE client capabilities that are relevant to the contract tests. This code should not need to be updated unless the SSE client has added or removed such capabilities.

## To run manually

```shell
bundle install
bundle exec ruby service.rb
```

This starts the service on port 8000. Then, in the directory where the test harness executable is:

```
./sse-contract-tests --url http://localhost:8000
```
