#!/bin/bash

set -e


wait_for_uri() {
  expected=$1
  shift
  uri=$1
  echo "Waiting for $uri to be available..."
  while true; do
    status=$(curl -s -w "%{http_code}" -o /dev/null $*)
    if [ "x$status" = "x$expected" ]; then
      break
    fi
    echo "$uri not up yet, waiting 2 seconds..."
    sleep 2
  done
  echo "$uri ready, continuing"
}

# Optional: Import test library
source dev-container-features-test-lib

# Feature specific tests
check "service" ls /etc/service/
check "entrypoint-exists" bash -c "ls /entrypoint.sh"
check "entrypoint-runs" bash -c "/entrypoint.sh couchbase-server &"

check "ready" wait_for_uri 200 http://127.0.0.1:8091/pools/default/buckets/travel-sample -u Administrator:password

# Report result
reportResults