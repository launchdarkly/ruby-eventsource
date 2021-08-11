#!/bin/bash

set -ue

# Standard publish.sh for Ruby-based projects - we can assume build.sh has already been run

#shellcheck source=/dev/null
source "$(dirname "$0")/gems-setup.sh"

# If we're running in CircleCI, the RubyGems credentials will be in an environment
# variable and should be copied to the variable the gem command expects
if [ -n "${LD_RELEASE_RUBYGEMS_API_KEY:-}" ]; then
  export GEM_HOST_API_KEY="${LD_RELEASE_RUBYGEMS_API_KEY}"
fi

# Since all Releaser builds are clean builds, we can assume that the only .gem file here
# is the one we just built
echo "Running gem push"
gem push ./*.gem || { echo "gem push failed" >&2; exit 1; }
