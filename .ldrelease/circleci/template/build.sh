#!/bin/bash

set -ue

# Standard build.sh for Ruby-based projects that publish a gem

echo "Using gem $(gem --version)"

#shellcheck source=/dev/null
source "$(dirname "$0")/gems-setup.sh"

echo; echo "Installing dependencies"
${BUNDLER_COMMAND} install

# Build Ruby Gem - this assumes there is a single .gemspec file in the main project directory
# Note that the gemspec must be able to get the project version either from $LD_RELEASE_VERSION,
# or from somewhere in the source code that the project-specific update-version.sh has updated.
echo "Running gem build"
gem build ./*.gemspec || { echo "gem build failed" >&2; exit 1; }
