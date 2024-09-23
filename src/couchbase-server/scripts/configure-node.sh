#!/bin/bash

# Log all subsequent commands to logfile. FD 3 is now the console
# for things we want to show up in "docker logs".
LOGFILE=/opt/couchbase/var/lib/couchbase/logs/container-startup.log
exec 3>&1 1>>${LOGFILE} 2>&1

CONFIG_DONE_FILE=/opt/couchbase/var/lib/couchbase/container-configured
config_done() {
  touch ${CONFIG_DONE_FILE}
  echo "Couchbase Admin UI: http://localhost:8091" \
     "\nLogin credentials: $COUCHBASE_USERNAME / $COUCHBASE_PASSWORD" | tee /dev/fd/3
  echo "Stopping config-couchbase service"
  sv stop /etc/service/config-couchbase
}

if [ -e ${CONFIG_DONE_FILE} ]; then
  echo "Container previously configured." | tee /dev/fd/3
  config_done
else
  echo "Configuring Couchbase Server.  Please wait (~60 sec)..." | tee /dev/fd/3
fi

export PATH=/opt/couchbase/bin:${PATH}

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

wait_for_response() {
  echo "Waiting for $expected response to be available..."
  while true; do
    status=$(curl http://127.0.0.1:8091/pools/default/buckets/$COUCHBASE_DEFAULT_BUCKET/scopes -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD | jq -c $*)
    if [ "$status" = "null" ]; then
      break
    fi
    echo "$expected reponse not up yet, waiting 2 seconds..."
    sleep 2
  done
  echo "$expected reponse ready, continuing"
}

panic() {
  cat <<EOF 1>&3

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Error during initial configuration - aborting container
Here's the log of the configuration attempt:
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF
  cat $LOGFILE 1>&3
  echo 1>&3
  kill -HUP 1
  sv stop /etc/service/config-couchbase &
  exit
}

couchbase_cli_check() {
  couchbase-cli $* || {
    echo Previous couchbase-cli command returned error code $?
    panic
  }
}

curl_check() {
  status=$(curl -sS -w "%{http_code}" -o /tmp/curl.txt $*)
  cat /tmp/curl.txt
  rm /tmp/curl.txt
  if [ "$status" -lt 200 -o "$status" -ge 300 ]; then
    echo
    echo Previous curl command returned HTTP status $status
    panic
  fi
}

wait_for_uri 200 http://127.0.0.1:8091/ui/index.html

echo "Setting memory quotas with curl:"
curl_check http://127.0.0.1:8091/pools/default -d memoryQuota=512 -d indexMemoryQuota=512 -d ftsMemoryQuota=512
echo

echo "Configuring Services with curl:"
curl_check http://127.0.0.1:8091/node/controller/setupServices -d services=kv%2Cn1ql%2Cindex%2Cfts
echo

echo "Setting up credentials with curl:"
curl_check http://127.0.0.1:8091/settings/web -d port=8091 -d username=$COUCHBASE_USERNAME -d $COUCHBASE_PASSWORD=$COUCHBASE_PASSWORD
echo

echo "Enabling memory-optimized indexes with curl:"
curl_check -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD -X POST http://127.0.0.1:8091/settings/indexes -d 'storageMode=memory_optimized'
echo

echo "Loading travel-sample with curl:"
curl_check -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD -X POST http://127.0.0.1:8091/sampleBuckets/install -d '["travel-sample"]'
echo

wait_for_uri 200 http://127.0.0.1:8091/pools/default/buckets/travel-sample -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD

echo "Creating hotels FTS index with curl:"
curl_check -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD -X PUT http://127.0.0.1:8094/api/index/hotels -H Content-Type:application/json -d @/opt/couchbase/create-index.json
rm /opt/couchbase/create-index.json
echo

echo "Creating RBAC 'admin' user on travel-sample bucket"
couchbase_cli_check user-manage --set \
  --rbac-username admin --rbac-password $COUCHBASE_PASSWORD \
  --roles 'bucket_full_access[travel-sample]' --auth-domain local \
  -c 127.0.0.1 -u $COUCHBASE_USERNAME -p $COUCHBASE_PASSWORD
echo


if [ -z "${COUCHBASE_DEFAULT_BUCKET}" ]; then
  echo "COUCHBASE_DEFAULT_BUCKET not defined, skip Bucket creation" | tee /dev/fd/3
else
  echo "COUCHBASE_DEFAULT_BUCKET found, creating bucket $COUCHBASE_DEFAULT_BUCKET" | tee /dev/fd/3
  curl_check -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD -X POST http://127.0.0.1:8091/pools/default/buckets/ -d name=$COUCHBASE_DEFAULT_BUCKET -d bucketType=couchbase  -d ramQuota=256
  wait_for_uri 200 http://127.0.0.1:8091/pools/default/buckets/$COUCHBASE_DEFAULT_BUCKET -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD
  if [ -z "${COUCHBASE_DEFAULT_SCOPE}" ]; then
    echo "COUCHBASE_DEFAULT_SCOPE not defined, skip Scope creation" | tee /dev/fd/3
  else
    echo "COUCHBASE_DEFAULT_SCOPE found, creating scope $COUCHBASE_DEFAULT_SCOPE." | tee /dev/fd/3
    if [ ${COUCHBASE_DEFAULT_SCOPE:0:1} == "_" ] || [ ${COUCHBASE_DEFAULT_SCOPE:0:1} == "%" ]; then 
      echo "Skip because name starts with _ or %"| tee /dev/fd/3
    else 
      curl_check -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD -X POST http://127.0.0.1:8091/pools/default/buckets/$COUCHBASE_DEFAULT_BUCKET/scopes -d name=$COUCHBASE_DEFAULT_SCOPE
      wait_for_response ".scopes | map(select(.name ==\"$COUCHBASE_DEFAULT_SCOPE\"))[0]"
    fi
    if [ -z "${COUCHBASE_DEFAULT_COLLECTION}" ]; then
      echo "COUCHBASE_DEFAULT_COLLECTION not defined, skip Collection creation" | tee /dev/fd/3
    else
      echo "COUCHBASE_DEFAULT_COLLECTION found, creating scope $COUCHBASE_DEFAULT_COLLECTION." | tee /dev/fd/3
    if [ ${COUCHBASE_DEFAULT_COLLECTION:0:1} == "_" ] || [ ${COUCHBASE_DEFAULT_COLLECTION:0:1} == "%" ]; then 
        echo "Skip because name starts with _ or %"| tee /dev/fd/3
      else 
        curl_check -u $COUCHBASE_USERNAME:$COUCHBASE_PASSWORD -X POST http://127.0.0.1:8091/pools/default/buckets/$COUCHBASE_DEFAULT_BUCKET/scopes/$COUCHBASE_DEFAULT_SCOPE -d name=$COUCHBASE_DEFAULT_COLLECTION
        wait_for_response ".scopes | map(select(.name ==\"$COUCHBASE_DEFAULT_SCOPE\"))[0].collections | map(select(.name == \"$COUCHBASE_DEFAULT_COLLECTION\"))[0]"
      fi
    fi
  fi
fi


echo "Configuration completed!" | tee /dev/fd/3

config_done