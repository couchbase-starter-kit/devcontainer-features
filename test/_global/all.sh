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

# Definition specific tests
check "cbsh root config" echo $USER
check "cbsh root config" echo $HOME
check "cbsh root config" ls /home/vscode/.cbsh
check "ready" wait_for_uri 200 http://127.0.0.1:8091/pools/default/buckets/travel-sample -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD
check "ready" wait_for_uri 200 http://127.0.0.1:8091/pools/default/buckets/$COUCHBASE_DEFAULT_BUCKET -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD
check "check for Couchbase Shell configuration" cbsh -c 'query "select 1"'
check "check shell env configuration" cbsh -c "cb-env" | grep $COUCHBASE_DEFAULT_BUCKET
check "check shell env configuration" cbsh -c "cb-env" | grep $COUCHBASE_DEFAULT_SCOPE
check "check shell env configuration" cbsh -c "cb-env" | grep $COUCHBASE_DEFAULT_COLLECTION

sleep 5 # wait for sync gateway to start
check "test sync gateway endpoint" bash -c 'curl -s http://127.0.0.1:4984/ | jq ".vendor.version" | grep "3.2"'

# Report result
reportResults