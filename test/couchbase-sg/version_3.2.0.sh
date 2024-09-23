#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Definition specific tests
check "couchbase sync gateway" cat /opt/couchbase-sync-gateway/manifest.txt  | grep "3.2.0"

# Report result
reportResults