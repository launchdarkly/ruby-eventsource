#!/bin/bash

# helper script to set GEM_HOME, PATH, and BUNDLER_COMMAND for Ruby - must be sourced, not executed

mkdir -p "${LD_RELEASE_TEMP_DIR}/gems"
export GEM_HOME="${LD_RELEASE_TEMP_DIR}/gems"
export PATH="${GEM_HOME}/bin:${PATH}"

# also, determine whether we'll need to run a specific version of Bundler

GEMSPEC_BUNDLER_VERSION=$(sed -n -e "s/.*['\"]bundler['\"], *['\"]\([^'\"]*\)['\"]/\1/p" ./*.gemspec | tr -d ' ')
if [ -n "${GEMSPEC_BUNDLER_VERSION}" ]; then
  BUNDLER_COMMAND="bundler _${GEMSPEC_BUNDLER_VERSION}_"
else
  BUNDLER_COMMAND="bundler"
fi
