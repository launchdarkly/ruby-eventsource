#!/usr/bin/env bash

# This script updates the version for the library and releases it to RubyGems
# It will only work if you have the proper credentials set up in ~/.gem/credentials

# It takes exactly one argument: the new version.
# It should be run from the root of this git repo like this:
#   ./scripts/release.sh 4.0.9

# When done you should commit and push the changes made.

set -uxe

VERSION=$1
GEM_NAME=ld-eventsource

echo "Starting $GEM_NAME release."

# Update version in version.rb
VERSION_RB_TEMP=./version.rb.tmp
sed "s/VERSION =.*/VERSION = \"${VERSION}\"/g" lib/$GEM_NAME/version.rb > ${VERSION_RB_TEMP}
mv ${VERSION_RB_TEMP} lib/$GEM_NAME/version.rb

# Build Ruby gem
gem build $GEM_NAME.gemspec

# Publish Ruby gem
gem push $GEM_NAME-${VERSION}.gem

echo "Done with $GEM_NAME release"