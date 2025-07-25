#!/bin/bash

set -e

# Get directory of running script
DIR="$(cd "$(dirname "$0")" && pwd)"

BUILD_REPOSITORY_LOCALPATH="$(realpath "${BUILD_REPOSITORY_LOCALPATH:-$DIR/../../..}")"
PROJECT_ROOT="${BUILD_REPOSITORY_LOCALPATH}/edgelet"

REVISION="${REVISION:-1}"
DEFAULT_VERSION="$(cat "$PROJECT_ROOT/version.txt")"
VERSION="${VERSION:-$DEFAULT_VERSION}"

DOCKER_VOLUME_MOUNTS=''

case "$PACKAGE_OS" in
    'redhat8')
        # Converts debian versioning to rpm version
        # deb 1.0.1~dev100 ~> rpm 1.0.1-0.1.dev100
        RPM_VERSION="$(echo "$VERSION" | cut -d"~" -f1)"
        RPM_TAG="$(echo "$VERSION" | cut -s -d"~" -f2)"
        if [ -n "$RPM_TAG" ]; then
            RPM_RELEASE="0.$REVISION.$RPM_TAG"
        else
            RPM_RELEASE="$REVISION"
        fi

        case "$PACKAGE_ARCH" in
            'amd64')
                DOCKER_IMAGE='redhat/ubi8:latest'
                ;;
        esac
        ;;

    'redhat9')
        # Converts debian versioning to rpm version
        # deb 1.0.1~dev100 ~> rpm 1.0.1-0.1.dev100
        RPM_VERSION="$(echo "$VERSION" | cut -d"~" -f1)"
        RPM_TAG="$(echo "$VERSION" | cut -s -d"~" -f2)"
        if [ -n "$RPM_TAG" ]; then
            RPM_RELEASE="0.$REVISION.$RPM_TAG"
        else
            RPM_RELEASE="$REVISION"
        fi

        case "$PACKAGE_ARCH" in
            'amd64')
                DOCKER_IMAGE='redhat/ubi9:latest'
                ;;
        esac
        ;;

    'debian11')
        DOCKER_IMAGE='mcr.microsoft.com/mirror/docker/library/debian:bullseye-slim'
        ;;

    'debian12')
        DOCKER_IMAGE='mcr.microsoft.com/mirror/docker/library/debian:bookworm-slim'
        ;;

    'ubuntu22.04')
        DOCKER_IMAGE='mcr.microsoft.com/mirror/docker/library/ubuntu:22.04'
        ;;
    
    'ubuntu24.04')
        DOCKER_IMAGE='mcr.microsoft.com/mirror/docker/library/ubuntu:24.04'
        ;;
esac

if [ -z "$DOCKER_IMAGE" ]; then
    echo "Unrecognized target [$PACKAGE_OS.$PACKAGE_ARCH]" >&2
    exit 1
fi

case "$PACKAGE_ARCH" in
    'amd64')
        MAKE_FLAGS="DPKGFLAGS='-b -us -uc -i'"
        ;;

    'arm32v7')
        RUST_TARGET='armv7-unknown-linux-gnueabihf'
        ;;

    'aarch64')
        RUST_TARGET='aarch64-unknown-linux-gnu'
        ;;
esac

if [ -n "$RUST_TARGET" ]; then
    RUST_TARGET_COMMAND="rustup target add $RUST_TARGET &&"
fi


case "$PACKAGE_OS.$PACKAGE_ARCH" in
    redhat8.amd64)
        SETUP_COMMAND=$'
            dnf distro-sync -y &&
            dnf install -y \
                curl git make rpm-build \
                gcc gcc-c++ \
                libcurl-devel libuuid-devel openssl-devel &&
            git config --global --add safe.directory \'*\'
        '
        ;;

     redhat9.amd64)
        SETUP_COMMAND=$'
            dnf distro-sync -y &&
            dnf install -y \
                git make rpm-build \
                gcc gcc-c++ \
                libcurl-devel libuuid-devel openssl-devel &&
            git config --global --add safe.directory \'*\'
        '
        ;;

    debian*.amd64)
        SETUP_COMMAND=$'
            export DEBIAN_FRONTEND=noninteractive
            export TZ=UTC
            apt-get update &&
            apt-get upgrade -y &&
            apt-get install -y --no-install-recommends \
                binutils build-essential ca-certificates curl debhelper file git make \
                gcc g++ pkg-config \
                libcurl4-openssl-dev libssl-dev uuid-dev &&
        '
        ;;

    debian*.arm32v7)
        SETUP_COMMAND=$'
            export DEBIAN_FRONTEND=noninteractive
            export TZ=UTC
            dpkg --add-architecture armhf &&
            apt-get update &&
            apt-get upgrade -y &&
            apt-get install -y --no-install-recommends \
                binutils build-essential ca-certificates curl debhelper file git make \
                gcc g++ \
                gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf \
                libcurl4-openssl-dev:armhf libssl-dev:armhf uuid-dev:armhf &&

            mkdir -p ~/.cargo &&
            echo \'[target.armv7-unknown-linux-gnueabihf]\' > ~/.cargo/config &&
            echo \'linker = "arm-linux-gnueabihf-gcc"\' >> ~/.cargo/config &&
            export ARMV7_UNKNOWN_LINUX_GNUEABIHF_OPENSSL_LIB_DIR=/usr/lib/arm-linux-gnueabihf &&
            export ARMV7_UNKNOWN_LINUX_GNUEABIHF_OPENSSL_INCLUDE_DIR=/usr/include &&
        '
        ;;

    debian*.aarch64)
        SETUP_COMMAND=$'
            export DEBIAN_FRONTEND=noninteractive
            export TZ=UTC
            dpkg --add-architecture arm64 &&
            apt-get update &&
            apt-get upgrade -y &&
            apt-get install -y --no-install-recommends \
                binutils build-essential ca-certificates curl debhelper file git make \
                gcc g++ \
                gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
                libcurl4-openssl-dev:arm64 libssl-dev:arm64 uuid-dev:arm64 &&

            mkdir -p ~/.cargo &&
            echo \'[target.aarch64-unknown-linux-gnu]\' > ~/.cargo/config &&
            echo \'linker = "aarch64-linux-gnu-gcc"\' >> ~/.cargo/config &&
            export AARCH64_UNKNOWN_LINUX_GNU_OPENSSL_LIB_DIR=/usr/lib/aarch64-linux-gnu &&
            export AARCH64_UNKNOWN_LINUX_GNU_OPENSSL_INCLUDE_DIR=/usr/include &&
        '
        ;;

    ubuntu22.04.amd64|ubuntu24.04.amd64)
        packages='binutils build-essential ca-certificates curl debhelper file git make gcc g++ \
            libcurl4-openssl-dev libssl-dev pkg-config uuid-dev'
        SETUP_COMMAND=$"
            export DEBIAN_FRONTEND=noninteractive
            export TZ=UTC
            apt-get update &&
            apt-get upgrade -y &&
            apt-get install -y --no-install-recommends $packages &&
        "
        ;;

    ubuntu22.04.arm32v7)
        packages='binutils build-essential ca-certificates curl debhelper file git make gcc g++ \
            gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf libcurl4-openssl-dev:armhf \
            libssl-dev:armhf uuid-dev:armhf'
        SETUP_COMMAND=$"
            export DEBIAN_FRONTEND=noninteractive
            export TZ=UTC
            sources=\"\$(cat /etc/apt/sources.list | grep -E '^[^#]')\" &&
            # Update existing repos to be specifically for amd64
            echo \"\$sources\" | sed -e 's/^deb /deb [arch=amd64] /g' > /etc/apt/sources.list &&
            # Add armhf repos
            echo \"\$sources\" |
                sed -e 's/^deb /deb [arch=armhf] /g' \
                    -e 's| http://archive.ubuntu.com/ubuntu/ | http://ports.ubuntu.com/ubuntu-ports/ |g' \
                    -e 's| http://security.ubuntu.com/ubuntu/ | http://ports.ubuntu.com/ubuntu-ports/ |g' \
                    >> /etc/apt/sources.list &&

            dpkg --add-architecture armhf &&
            apt-get update &&
            apt-get upgrade -y &&
            apt-get install -y --no-install-recommends $packages &&
            mkdir -p ~/.cargo &&
            echo '[target.armv7-unknown-linux-gnueabihf]' > ~/.cargo/config &&
            echo 'linker = \"arm-linux-gnueabihf-gcc\"' >> ~/.cargo/config &&
            export ARMV7_UNKNOWN_LINUX_GNUEABIHF_OPENSSL_LIB_DIR=/usr/lib/arm-linux-gnueabihf &&
            export ARMV7_UNKNOWN_LINUX_GNUEABIHF_OPENSSL_INCLUDE_DIR=/usr/include &&
        "
        ;;

    # Ubuntu 24.04 uses DEB822 format for sources.list, so we have to handle it differently
    ubuntu24.04.arm32v7)
        packages='binutils build-essential ca-certificates curl debhelper file git make gcc g++ \
            gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf libcurl4-openssl-dev:armhf \
            libssl-dev:armhf uuid-dev:armhf'

        SETUP_COMMAND=$"
            export DEBIAN_FRONTEND=noninteractive
            export TZ=UTC
            # Update existing repos to be specifically for amd64
            sed -ie '/^Architectures:/d' /etc/apt/sources.list.d/ubuntu.sources &&
            sed -ie '/^Components:/a Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources &&
            # Add arch-specific repos
            </etc/apt/sources.list.d/ubuntu.sources sed \
                -e 's/^Architectures: amd64/Architectures: armhf/g' \
                -e 's|URIs: http://archive.ubuntu.com/ubuntu/|URIs: http://ports.ubuntu.com/ubuntu-ports/|g' \
                -e 's|URIs: http://security.ubuntu.com/ubuntu/|URIs: http://ports.ubuntu.com/ubuntu-ports/|g' \
                >/etc/apt/sources.list.d/ubuntu.ports.sources &&

            dpkg --add-architecture armhf &&
            apt-get update &&
            apt-get upgrade -y &&
            apt-get install -y --no-install-recommends $packages &&
            mkdir -p ~/.cargo &&
            echo '[target.armv7-unknown-linux-gnueabihf]' > ~/.cargo/config &&
            echo 'linker = \"arm-linux-gnueabihf-gcc\"' >> ~/.cargo/config &&
            export ARMV7_UNKNOWN_LINUX_GNUEABIHF_OPENSSL_LIB_DIR=/usr/lib/arm-linux-gnueabihf &&
            export ARMV7_UNKNOWN_LINUX_GNUEABIHF_OPENSSL_INCLUDE_DIR=/usr/include &&
        "
        ;;

    ubuntu22.04.aarch64)
        packages='binutils build-essential ca-certificates curl debhelper file git make gcc \
            g++ gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libcurl4-openssl-dev:arm64 \
            libssl-dev:arm64 uuid-dev:arm64'
        SETUP_COMMAND=$"
            export DEBIAN_FRONTEND=noninteractive
            export TZ=UTC
            sources=\"\$(cat /etc/apt/sources.list | grep -E '^[^#]')\" &&
            # Update existing repos to be specifically for amd64
            echo \"\$sources\" | sed -e 's/^deb /deb [arch=amd64] /g' > /etc/apt/sources.list &&
            # Add arm64 repos
            echo \"\$sources\" |
                sed -e 's/^deb /deb [arch=arm64] /g' \
                    -e 's| http://archive.ubuntu.com/ubuntu/ | http://ports.ubuntu.com/ubuntu-ports/ |g' \
                    -e 's| http://security.ubuntu.com/ubuntu/ | http://ports.ubuntu.com/ubuntu-ports/ |g' \
                    >> /etc/apt/sources.list &&

            dpkg --add-architecture arm64 &&
            apt-get update &&
            apt-get upgrade -y &&
            apt-get install -y --no-install-recommends $packages &&
            mkdir -p ~/.cargo &&
            echo '[target.aarch64-unknown-linux-gnu]' > ~/.cargo/config &&
            echo 'linker = \"aarch64-linux-gnu-gcc\"' >> ~/.cargo/config &&
            export AARCH64_UNKNOWN_LINUX_GNU_OPENSSL_LIB_DIR=/usr/lib/aarch64-linux-gnu &&
            export AARCH64_UNKNOWN_LINUX_GNU_OPENSSL_INCLUDE_DIR=/usr/include &&
        "
        ;;

    # Ubuntu 24.04 uses DEB822 format for sources.list, so we have to handle it differently
    ubuntu24.04.aarch64)
        packages='binutils build-essential ca-certificates curl debhelper file git make gcc \
            g++ gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libcurl4-openssl-dev:arm64 \
            libssl-dev:arm64 uuid-dev:arm64'
        SETUP_COMMAND=$"
            export DEBIAN_FRONTEND=noninteractive
            export TZ=UTC
            # Update existing repos to be specifically for amd64
            sed -ie '/^Architectures:/d' /etc/apt/sources.list.d/ubuntu.sources &&
            sed -ie '/^Components:/a Architectures: amd64' /etc/apt/sources.list.d/ubuntu.sources &&
            # Add arch-specific repos
            </etc/apt/sources.list.d/ubuntu.sources sed \
                -e 's/^Architectures: amd64/Architectures: arm64/g' \
                -e 's|URIs: http://archive.ubuntu.com/ubuntu/|URIs: http://ports.ubuntu.com/ubuntu-ports/|g' \
                -e 's|URIs: http://security.ubuntu.com/ubuntu/|URIs: http://ports.ubuntu.com/ubuntu-ports/|g' \
                >/etc/apt/sources.list.d/ubuntu.ports.sources &&

            dpkg --add-architecture arm64 &&
            apt-get update &&
            apt-get upgrade -y &&
            apt-get install -y --no-install-recommends $packages &&
            mkdir -p ~/.cargo &&
            echo '[target.aarch64-unknown-linux-gnu]' > ~/.cargo/config &&
            echo 'linker = \"aarch64-linux-gnu-gcc\"' >> ~/.cargo/config &&
            export AARCH64_UNKNOWN_LINUX_GNU_OPENSSL_LIB_DIR=/usr/lib/aarch64-linux-gnu &&
            export AARCH64_UNKNOWN_LINUX_GNU_OPENSSL_INCLUDE_DIR=/usr/include &&
        "
        ;;
esac

if [ -z "$SETUP_COMMAND" ]; then
    echo "Unrecognized target [$PACKAGE_OS.$PACKAGE_ARCH]" >&2
    exit 1
fi

case "$PACKAGE_OS" in
    redhat8|redhat9)
        case "$PACKAGE_ARCH" in
            amd64)
                MAKE_TARGET_DIR='target/release'
                ;;
        esac

        MAKE_COMMAND="mkdir -p /project/edgelet/target/rpmbuild"
        MAKE_COMMAND="$MAKE_COMMAND && cd /project/edgelet/target/rpmbuild"
        MAKE_COMMAND="$MAKE_COMMAND && mkdir -p RPMS SOURCES SPECS SRPMS BUILD"
        MAKE_COMMAND="$MAKE_COMMAND && cd /project/edgelet"
        MAKE_COMMAND="$MAKE_COMMAND && make rpm-dist 'TARGET=target/rpmbuild/SOURCES' 'VERSION=$VERSION' 'REVISION=$REVISION'"
        MAKE_COMMAND="$MAKE_COMMAND && make rpm rpmbuilddir=/project/edgelet/target/rpmbuild 'TARGET=$MAKE_TARGET_DIR' 'VERSION=$VERSION' 'REVISION=$REVISION' 'CARGOFLAGS=--manifest-path ./Cargo.toml $CARGO_TARGET_FLAG' RPMBUILDFLAGS='-v -bb --clean --define \"_topdir /project/edgelet/target/rpmbuild\" $RPMBUILD_TARGET_FLAG'"
        ;;

    *)
        case "$PACKAGE_ARCH" in
            amd64)
                ;;
            arm32v7)
                MAKE_FLAGS="'CARGOFLAGS=--target armv7-unknown-linux-gnueabihf'"
                MAKE_FLAGS="$MAKE_FLAGS 'TARGET=target/armv7-unknown-linux-gnueabihf/release'"
                MAKE_FLAGS="$MAKE_FLAGS 'DPKGFLAGS=-b -us -uc -i --host-arch armhf'"
                ;;
            aarch64)
                MAKE_FLAGS="'CARGOFLAGS=--target aarch64-unknown-linux-gnu'"
                MAKE_FLAGS="$MAKE_FLAGS 'TARGET=target/aarch64-unknown-linux-gnu/release'"
                MAKE_FLAGS="$MAKE_FLAGS 'DPKGFLAGS=-b -us -uc -i --host-arch arm64 --host-type aarch64-linux-gnu --target-type aarch64-linux-gnu'"
                ;;
        esac

        MAKE_COMMAND="make deb 'VERSION=$VERSION' 'REVISION=$REVISION' $MAKE_FLAGS"
        ;;
esac


docker run --rm \
    --user root \
    -e 'USER=root' \
    -v "$BUILD_REPOSITORY_LOCALPATH:/project" \
    -i \
    $DOCKER_VOLUME_MOUNTS \
    "$DOCKER_IMAGE" \
    sh -c "
        set -e &&

        cat /etc/os-release &&

        $SETUP_COMMAND

        echo 'Installing rustup' &&
        curl -sSLf https://sh.rustup.rs | sh -s -- -y &&
        . ~/.cargo/env &&

        # aziot-edged
        cd /project/edgelet &&
        $RUST_TARGET_COMMAND
        $MAKE_COMMAND
    "

find "$PROJECT_ROOT" -name '*.deb'
find "$PROJECT_ROOT" -name '*.ddeb'
find "$PROJECT_ROOT" -name '*.rpm'
