#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "couchbase" couchbase-server --version | grep "7.6.3"

# Report result
reportResults