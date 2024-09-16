#!/usr/bin/env bash

CLI_VERSION=${CBSHVERSION:-"1.0.0"}

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
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

# Github direct download
install_using_github() {
    check_packages wget
    # Install ARM or x86 version of hugo based on current machine architecture
    architecture="$(uname -m)"
    if [ "${architecture}" != "amd64" ] && [ "${architecture}" != "x86_64" ] && [ "${architecture}" != "arm64" ] && [ "${architecture}" != "aarch64" ]; then
        echo "(!) Architecture $architecture unsupported"
        exit 1
    fi

    if [ "${architecture}" == "amd64" ] || [ "${architecture}" == "x86_64" ]; then
        dpkgArch="x86_64"
    fi
    if [ "${architecture}" == "arm64" ] || [ "${architecture}" == "aarch64" ]; then
        dpkgArch="aarch64"
    fi
    echo $CLI_VERSION

    find_version_from_git_tags CLI_VERSION https://github.com/couchbaselabs/couchbase-shell
    cli_filename="cbsh-${dpkgArch}-unknown-linux-gnu.tar.gz"
    mkdir -p /tmp/cbsh
    pushd /tmp/cbsh
    wget https://github.com/couchbaselabs/couchbase-shell/releases/download/v${CLI_VERSION}/${cli_filename}
    exit_code=$?
    set -e
    if [ "$exit_code" != "0" ]; then
        # Handle situation where git tags are ahead of what was is available to actually download
        echo "(!) cbsh version ${CLI_VERSION} failed to download. Attempting to fall back one version to retry..."
        find_prev_version_from_git_tags CLI_VERSION https://github.com/couchbaselabs/couchbase-shell
        wget https://github.com/cli/cli/releases/download/v${CLI_VERSION}/${cli_filename}
    fi

    tar -xzvf /tmp/cbsh/${cli_filename}
    cp cbsh /usr/bin/cbsh
    popd
    rm -rf /tmp/cbsh
}

# Figure out correct version of a three part version number is not passed
find_version_from_git_tags() {
    local variable_name=$1
    local requested_version=${!variable_name}
    if [ "${requested_version}" = "none" ]; then return; fi
    local repository=$2
    local prefix=${3:-"tags/v"}
    local separator=${4:-"."}
    local last_part_optional=${5:-"false"}    
    if [ "$(echo "${requested_version}" | grep -o "." | wc -l)" != "2" ]; then
        local escaped_separator=${separator//./\\.}
        local last_part
        if [ "${last_part_optional}" = "true" ]; then
            last_part="(${escaped_separator}[0-9]+)?"
        else
            last_part="${escaped_separator}[0-9]+"
        fi
        local regex="${prefix}\\K[0-9]+${escaped_separator}[0-9]+${last_part}$"
        local version_list="$(git ls-remote --tags ${repository} | grep -oP "${regex}" | tr -d ' ' | tr "${separator}" "." | sort -rV)"
        if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "current" ] || [ "${requested_version}" = "lts" ]; then
            declare -g ${variable_name}="$(echo "${version_list}" | head -n 1)"
        else
            set +e
            declare -g ${variable_name}="$(echo "${version_list}" | grep -E -m 1 "^${requested_version//./\\.}([\\.\\s]|$)")"
            set -e
        fi
    fi
    if [ -z "${!variable_name}" ] || ! echo "${version_list}" | grep "^${!variable_name//./\\.}$" > /dev/null 2>&1; then
        echo -e "Invalid ${variable_name} value: ${requested_version}\nValid values:\n${version_list}" >&2
        exit 1
    fi
    echo "${variable_name}=${!variable_name}"
}

# Use semver logic to decrement a version number then look for the closest match
find_prev_version_from_git_tags() {
    local variable_name=$1
    local current_version=${!variable_name}
    local repository=$2
    # Normally a "v" is used before the version number, but support alternate cases
    local prefix=${3:-"tags/v"}
    # Some repositories use "_" instead of "." for version number part separation, support that
    local separator=${4:-"."}
    # Some tools release versions that omit the last digit (e.g. go)
    local last_part_optional=${5:-"false"}
    # Some repositories may have tags that include a suffix (e.g. actions/node-versions)
    local version_suffix_regex=$6
    # Try one break fix version number less if we get a failure. Use "set +e" since "set -e" can cause failures in valid scenarios.
    set +e
        major="$(echo "${current_version}" | grep -oE '^[0-9]+' || echo '')"
        minor="$(echo "${current_version}" | grep -oP '^[0-9]+\.\K[0-9]+' || echo '')"
        breakfix="$(echo "${current_version}" | grep -oP '^[0-9]+\.[0-9]+\.\K[0-9]+' 2>/dev/null || echo '')"

        if [ "${minor}" = "0" ] && [ "${breakfix}" = "0" ]; then
            ((major=major-1))
            declare -g ${variable_name}="${major}"
            # Look for latest version from previous major release
            find_version_from_git_tags "${variable_name}" "${repository}" "${prefix}" "${separator}" "${last_part_optional}"
        # Handle situations like Go's odd version pattern where "0" releases omit the last part
        elif [ "${breakfix}" = "" ] || [ "${breakfix}" = "0" ]; then
            ((minor=minor-1))
            declare -g ${variable_name}="${major}.${minor}"
            # Look for latest version from previous minor release
            find_version_from_git_tags "${variable_name}" "${repository}" "${prefix}" "${separator}" "${last_part_optional}"
        else
            ((breakfix=breakfix-1))
            if [ "${breakfix}" = "0" ] && [ "${last_part_optional}" = "true" ]; then
                declare -g ${variable_name}="${major}.${minor}"
            else 
                declare -g ${variable_name}="${major}.${minor}.${breakfix}"
            fi
        fi
    set -e
}

export DEBIAN_FRONTEND=noninteractive

# Install curl, apt-transport-https, curl, gpg, or dirmngr, git if missing
check_packages curl ca-certificates apt-transport-https dirmngr gnupg2
if ! type git > /dev/null 2>&1; then
    check_packages git
fi

# Install Couchbase SHell
echo "Downloading Couchbase Shell..."
install_using_github
# install with sources
install_using_sources() {
    # Install curl, apt-transport-https, curl, gpg, or dirmngr, git if missing
    check_packages clang librust-openssl-sys-dev librust-openssl-probe-dev librust-openssl-dev
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain 1.80.0 \
            -c rls rust-analysis rust-src rustfmt clippy 
    . "$HOME/.cargo/env" 
    printf '%s\n'    'export CARGO_HOME=/root/.cargo' \
                            'mkdir -m 0755 -p "$CARGO_HOME/bin" 2>/dev/null' \
                            'export PATH=$CARGO_HOME/bin:$PATH' \
                            'test ! -e "$CARGO_HOME/bin/rustup" && mv "$(command -v rustup)" "$CARGO_HOME/bin"' >> $HOME/.bashrc 
    ln -s /root/.cargo/bin/cbsh /usr/bin/cbsh 
    cargo install --git https://github.com/couchbaselabs/couchbase-shell 
}
#install_using_sources

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"