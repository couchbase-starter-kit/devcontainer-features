#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "couchbase-shell" cbsh --version | grep "1.0.0"

# Report result
reportResults