#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Feature specific tests
check "couchbase sync gateway" sync_gateway -h 

# Report result
reportResults