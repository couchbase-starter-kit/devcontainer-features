#!/usr/bin/env bash
# Default: Exit on any failure.
set -e

# Clean up
rm -rf /var/lib/apt/lists/*

# Setup STDERR.
err() {
    echo "(!) $*" >&2
}

if [ "$(id -u)" -ne 0 ]; then
    err 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
        if id -u ${CURRENT_USER} > /dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi

apt_get_update()
{
    if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
    fi
}

setup_couchbase() {
    # Update VARIANT.txt to indicate we're running in our Docker image
    sed -i -e '1 s/$/\/docker/' /opt/couchbase/VARIANT.txt

    # Add runit service script for couchbase-server
    mkdir -p /etc/service/couchbase-server/
    cp $BASE_DIR/run /etc/service/couchbase-server/run
    mkdir -p /etc/service/couchbase-server/supervise
    chown -R couchbase:couchbase /etc/service /etc/service/couchbase-server/supervise

    # Add dummy script for commands invoked by cbcollect_info that
    # make no sense in a Docker container
    cp $BASE_DIR/dummy.sh /usr/local/bin/
    ln -s dummy.sh /usr/local/bin/iptables-save
    ln -s dummy.sh /usr/local/bin/lvdisplay
    ln -s dummy.sh /usr/local/bin/vgdisplay
    ln -s dummy.sh /usr/local/bin/pvdisplay

    # Fix curl RPATH if necessary - if curl.real exists, it's a new
    # enough package that we don't need to do anything. If not, it
    # may be OK, but just fix it
    if [ ! -e /opt/couchbase/bin/curl.real ]; then
        ${UPDATE_COMMAND};
        apt-get install -y chrpath;
        chrpath -r '$ORIGIN/../lib' /opt/couchbase/bin/curl;
        apt-get remove -y chrpath;
        apt-get autoremove -y;
        ${CLEANUP_COMMAND};
    fi
    
    mkdir -p /etc/service/config-couchbase/
    cp $BASE_DIR/configure-node.sh /etc/service/config-couchbase/run
    chown -R couchbase:couchbase /etc/service
    cp $BASE_DIR/create-index.json /opt/couchbase

    # Add bootstrap script
    cp $BASE_DIR/entrypoint.sh /entrypoint.sh

    # Add couchbase-shell config
    cp $BASE_DIR/cbshconfig /opt/couchbase/cbshconfig
    cp $BASE_DIR/installCbshConfig.sh /opt/couchbase/installCbshConfig.sh
}

install_couchbase() {
    # Install dependencies
    check_packages wget tzdata lsof lshw sysstat net-tools numactl bzip2 sudo git make ca-certificates curl gcc clang
    # Install runit script
    cd /usr/src 
    git clone https://github.com/couchbasedeps/runit/
    cd runit 
    git checkout edb631449d89d5b452a5992c6ffaa1e384fea697 
    ./package/compile 
    cp ./command/* /sbin/
    
    COUCHBASE_VERSION=${CBVERSION:-"7.6.3"}
    USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"
    dpkgArch="$(dpkg --print-architecture)" 

    CB_RELEASE_URL=https://packages.couchbase.com/releases/$COUCHBASE_VERSION
    CB_PACKAGE=couchbase-server-enterprise_$COUCHBASE_VERSION-linux_$dpkgArch.deb
    CB_PACKAGE_SHA256=$CB_PACKAGE.sha256

    wget -N --no-verbose $CB_RELEASE_URL/$CB_PACKAGE 
    CB_SHA256=`curl $CB_RELEASE_URL/$CB_PACKAGE_SHA256`

    { ${CB_SKIP_CHECKSUM} || echo "$CB_SHA256  $CB_PACKAGE" | sha256sum -c - ; } 
    apt-get install -y ./$CB_PACKAGE 
}

export DEBIAN_FRONTEND=noninteractive
export INSTALL_DONT_START_SERVER=1 
CLEANUP_COMMAND="rm -rf /var/lib/apt/lists/*  /var/tmp/*" #/tmp/*

export BASE_DIR=$PWD/scripts

# Create Couchbase user with UID 1000 (necessary to match default
# boot2docker UID)
groupadd -g 1000 couchbase && useradd couchbase -u 1000 -g couchbase -M

install_couchbase

setup_couchbase

# Clean up
rm -rf /var/lib/apt/lists/*
#rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

rm -f ./$CB_PACKAGE 
${CLEANUP_COMMAND} 
rm -rf  /var/tmp/*

echo "Done!"