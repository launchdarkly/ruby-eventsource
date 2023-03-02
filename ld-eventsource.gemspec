# coding: utf-8

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "ld-eventsource/version"

# rubocop:disable Metrics/BlockLength
Gem::Specification.new do |spec|
  spec.name          = "ld-eventsource"
  spec.version       = SSE::VERSION
  spec.authors       = ["LaunchDarkly"]
  spec.email         = ["team@launchdarkly.com"]
  spec.summary       = "LaunchDarkly SSE client"
  spec.description   = "LaunchDarkly SSE client for Ruby"
  spec.homepage      = "https://github.com/launchdarkly/ruby-eventsource"
  spec.license       = "Apache-2.0"

  spec.files         = FileList["lib/**/*", "README.md", "LICENSE"]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "2.2.10"
  spec.add_development_dependency "rspec", "~> 3.2"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.3.0"
  spec.add_development_dependency "webrick", "~> 1.7"

  spec.add_runtime_dependency "concurrent-ruby", "~> 1.0"
  spec.add_runtime_dependency "http", ">= 4.4.1", "< 6.0.0"
end
