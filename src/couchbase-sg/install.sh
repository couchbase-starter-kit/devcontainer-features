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

setup_sg() {
    mkdir /opt/couchbase-sync-gateway/data
    mkdir -p /etc/service/couchbase-sg/supervise
    cp $BASE_DIR/scripts/run /etc/service/couchbase-sg/run
    chown -R couchbase:couchbase /etc/service /etc/service/couchbase-sg/supervise
    mkdir /etc/sync_gateway
    cp $BASE_DIR/scripts/config.json /etc/sync_gateway/config.json
    chown -R sync_gateway:sync_gateway /etc/sync_gateway
    mkdir -p /var/log/sync_gateway
    chown sync_gateway:sync_gateway /var/log/sync_gateway
}

install_sg() {
    # Install dependencies
    check_packages curl lsb-release systemctl wget
    SG_VERSION=${SGVERSION:-"3.2.0"}
    SGW_PACKAGE="http://packages.couchbase.com/releases/couchbase-sync-gateway/${SG_VERSION}/couchbase-sync-gateway-enterprise_${SG_VERSION}_@@ARCH@@.deb"
    
    SGW_PACKAGE=$(echo "${SGW_PACKAGE}" | sed -e "s/@@ARCH@@/$(uname -m)/") 
    SGW_PACKAGE_FILENAME=$(echo "couchbase-sync-gateway-enterprise_${SG_VERSION}_@@ARCH@@.deb" | sed -e "s/@@ARCH@@/$(uname -m)/") 
    wget "${SGW_PACKAGE}" 
    apt install -y ./"${SGW_PACKAGE_FILENAME}" 
    rm "${SGW_PACKAGE_FILENAME}" 
    apt autoremove 
    apt clean
}

export DEBIAN_FRONTEND=noninteractive

export BASE_DIR=$PWD
CLEANUP_COMMAND="rm -rf /var/lib/apt/lists/*  /var/tmp/*" # /tmp/*


install_sg
setup_sg

# Clean up
rm -f ./$SGW_PACKAGE 
${CLEANUP_COMMAND} 

echo "Done!"