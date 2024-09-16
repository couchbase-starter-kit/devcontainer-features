#!/bin/sh

# Configure Couchbase Shell for Root and any found users
ls /home | xargs -i  mkdir  /home/{}/.cbsh
ls /home | xargs -i  cp opt/couchbase/cbshconfig /home/{}/.cbsh/config
mkdir /root/.cbsh
cp /opt/couchbase/cbshconfig /root/.cbsh/config