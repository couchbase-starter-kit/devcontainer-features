#!/bin/bash

cat << EOF > /opt/couchbase/cbshconfig

version = 1

[[cluster]]
identifier = "local"
connstr = "$COUCHBASE_CONNECTION_STRING"
default-bucket = "$COUCHBASE_DEFAULT_BUCKET"
default-scope = "$COUCHBASE_DEFAULT_SCOPE"
default-collection = "$COUCHBASE_DEFAULT_COLLECTION"
username = "$COUCHBASE_USERNAME"
password = "$COUCHBASE_PASSWORD"
data-timeout = "5s"
connect-timeout = "1m 15s"
search-timeout = "1m 15s"
analytics-timeout = "1m 15s"
management-timeout = "1m 15s"
tls-enabled = false
tls-accept-all-certs = false

EOF


# Configure Couchbase Shell for Root and any found users
ls /home | xargs -i  mkdir  /home/{}/.cbsh
ls /home | xargs -i  cp opt/couchbase/cbshconfig /home/{}/.cbsh/config
mkdir /root/.cbsh
cp /opt/couchbase/cbshconfig /root/.cbsh/config