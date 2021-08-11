#!/bin/bash

set -ue

# Standard test.sh for Ruby-based projects

#shellcheck source=/dev/null
source "$(dirname "$0")/gems-setup.sh"

${BUNDLER_COMMAND} exec rspec spec
