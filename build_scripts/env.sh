#!/bin/bash
# General Klipper Mod Environment, sourced by build scripts

ENV_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Git root dir
export GIT_ROOT=$(realpath "$ENV_DIR/..")
# Build system scripts / configuration files
export BUILD_SCRIPTS=$GIT_ROOT/build_scripts
# Build system overlays
export BUILD_OVERLAYS=$GIT_ROOT/build_overlays
# Location for all build artifacts
export BUILD_OUT=$GIT_ROOT/build_output
# Location for all packaged artifcates we want to keep
export BUILD_PACKAGE=$BUILD_OUT/packages

# Canonical Buildroot source. The revision is checked by build.sh before any
# Buildroot output is configured. AD5M_BUILDROOT_DIR is useful for a separate
# checkout, but it must match the tracked buildroot-revision contract.
export BUILDROOT_GIT=${AD5M_BUILDROOT_DIR:-$GIT_ROOT/../buildroot-flashforge-ad5m}
export BUILDROOT_OUT=$BUILD_OUT/buildroot
export BUILDROOT_SDK=$BUILDROOT_OUT/sdk
export BUILDROOT_EXT=$BUILD_SCRIPTS/buildroot
export BUILDROOT_CONFIGS=$BUILD_SCRIPTS/buildroot/configs
export BUILDROOT_CONTRACT_FILE=$BUILD_SCRIPTS/buildroot/buildroot-revision

### Log helper functions

log_color() {
  COLOR='\033[0;'$1'm'
  NC='\033[0m'
  echo -e "* ${COLOR}$2${NC}"
}

log_info() {
  # Cyan
  log_color "36" "$1"
}

log_warn() {
  # Light Red
  log_color "33" "Warning: $1"
}

log_error() {
  # Red
  log_color "31" "Error: $1"
}
