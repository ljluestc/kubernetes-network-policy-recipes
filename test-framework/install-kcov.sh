#!/usr/bin/env bash
# Install kcov for bash code coverage
# Supports Ubuntu/Debian and macOS

set -euo pipefail

KCOV_VERSION="${KCOV_VERSION:-42}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local}"

echo "Installing kcov v${KCOV_VERSION}..."

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Detected Linux, installing build dependencies..."

    # Install dependencies
    sudo apt-get update
    sudo apt-get install -y \
        cmake \
        g++ \
        pkg-config \
        libcurl4-openssl-dev \
        libelf-dev \
        libdw-dev \
        binutils-dev \
        libiberty-dev \
        zlib1g-dev \
        python3

    # Download and build kcov
    cd /tmp
    rm -rf kcov-${KCOV_VERSION}
    wget https://github.com/SimonKagstrom/kcov/archive/v${KCOV_VERSION}.tar.gz
    tar xzf v${KCOV_VERSION}.tar.gz
    cd kcov-${KCOV_VERSION}

    mkdir build
    cd build
    cmake ..
    make
    sudo make install

    echo "kcov installed successfully to ${INSTALL_DIR}/bin/kcov"
    kcov --version

elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS, installing via Homebrew..."

    if ! command -v brew &> /dev/null; then
        echo "Error: Homebrew not found. Please install Homebrew first."
        exit 1
    fi

    brew install kcov
    kcov --version

else
    echo "Error: Unsupported OS: $OSTYPE"
    exit 1
fi

echo "kcov installation complete!"
