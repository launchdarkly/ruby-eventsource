#!/bin/bash

set -ue

echo "Using gem $(gem --version)"

#shellcheck source=/dev/null
source "$(dirname "$0")/gems-setup.sh"

# If the gemspec specifies a certain version of bundler, we need to make sure we install that version.
echo "Installing bundler"
if [ -n "${GEMSPEC_BUNDLER_VERSION:-}" ]; then
  GEMSPEC_OPTIONS="-v ${GEMSPEC_BUNDLER_VERSION}"
else
  GEMSPEC_OPTIONS=""
fi
gem install bundler ${GEMSPEC_OPTIONS} || { echo "installing bundler failed" >&2; exit 1; }
