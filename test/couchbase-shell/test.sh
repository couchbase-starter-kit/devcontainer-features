#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Feature specific tests
check "couchbase-shell" cbsh --version

# Report result
reportResults