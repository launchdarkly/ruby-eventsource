#!/bin/bash

set -ue

# Standard update-version.sh for Ruby-based projects - this will work only if the version string
# is in a source file under lib/ that has a line like his: VERSION = "2.0.0"

"$(dirname "$0")/../update-version-constant.sh" lib '*.rb'
