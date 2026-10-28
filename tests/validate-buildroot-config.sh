#!/usr/bin/env bash
# Configure the lite variant against the recorded Buildroot checkout.  This is
# deliberately separate from validate-static.sh because it initialises an
# output directory, albeit only one created under TMPDIR for this invocation.
set -euo pipefail

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf 'ok: %s\n' "$*"
}

if [[ $# -ne 1 ]]; then
    fail "usage: $0 <ad5m_enhanced_mod-root>"
fi

repo_root=$(cd -- "$1" && pwd -P) || fail "cannot resolve repository root: $1"
case "/$repo_root/" in
    */build_output/*)
        fail "refusing a build-output path as the repository root: $repo_root"
        ;;
esac

[[ -f "$repo_root/build_scripts/build.sh" ]] || \
    fail "missing build wrapper under $repo_root"
[[ -f "$repo_root/build_scripts/buildroot/buildroot-revision" ]] || \
    fail "missing Buildroot contract file"

buildroot_dir=${AD5M_BUILDROOT_DIR:-"$repo_root/../buildroot-flashforge-ad5m"}
buildroot_dir=$(cd -- "$buildroot_dir" && pwd -P) || \
    fail "cannot resolve canonical Buildroot checkout: $buildroot_dir"
[[ -f "$buildroot_dir/Makefile" ]] || fail "missing Buildroot Makefile: $buildroot_dir"

expected_revision=$(tr -d '[:space:]' < "$repo_root/build_scripts/buildroot/buildroot-revision")
[[ "$expected_revision" =~ ^[0-9a-f]{40}$ ]] || \
    fail "invalid recorded Buildroot revision: $expected_revision"
actual_revision=$(git -C "$buildroot_dir" rev-parse HEAD 2>/dev/null) || \
    fail "Buildroot source is not a Git checkout: $buildroot_dir"
[[ "$actual_revision" == "$expected_revision" ]] || \
    fail "Buildroot revision mismatch: expected $expected_revision, found $actual_revision"
[[ -z "$(git -C "$buildroot_dir" status --porcelain --untracked-files=normal)" ]] || \
    fail "Buildroot checkout has uncommitted changes: $buildroot_dir"
pass "canonical Buildroot revision and worktree match the recorded contract"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ad5m-buildroot-config.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT
temp_output="$tmp_dir/build_output"
credentials_dir="$tmp_dir/credentials"
root_password_hash="$credentials_dir/root-password.sha256"
mkdir -m 700 "$credentials_dir"

expect_prepare_rejected() {
    local label=$1 password_file=$2 expected_error=$3 log_file

    log_file="$tmp_dir/$label.log"
    if AD5M_ROOT_PASSWORD_HASH_FILE="$password_file" \
        AD5M_BUILDROOT_DIR="$buildroot_dir" \
        AD5M_BUILD_OUT="$tmp_dir/rejected-$label" \
        "$repo_root/build_scripts/build.sh" prepare_variant lite >"$log_file" 2>&1; then
        fail "variant preparation unexpectedly accepted $label root-password input"
    fi
    grep -Fq "$expected_error" "$log_file" || \
        fail "variant preparation rejected $label input for an unexpected reason"
}

expect_prepare_rejected missing "$credentials_dir/missing.sha256" \
    'Per-printer root password hash not found'
printf '%s\n' 'not-a-password-hash' > "$credentials_dir/malformed.sha256"
chmod 600 "$credentials_dir/malformed.sha256"
expect_prepare_rejected malformed "$credentials_dir/malformed.sha256" \
    'Root password hash is not a valid SHA-256-crypt value'
printf '%s\n' '$5$ad5mtestsalt$agH/idcAiVhRGQO/H4gI3XdiAij8M5Z2jmOmwjNBLA8' > "$credentials_dir/open.sha256"
chmod 644 "$credentials_dir/open.sha256"
expect_prepare_rejected broadly-readable "$credentials_dir/open.sha256" \
    'Root password hash must not be readable by group or others'
pass "missing, malformed, and broadly readable root-password inputs fail before configuration"

# This is a non-secret fixture hash for the text "ad5m-validation-only".  It
# exercises Buildroot's pre-hashed-password path without putting a password in
# the repository or the generated configuration.
printf '%s\n' '$5$ad5mtestsalt$agH/idcAiVhRGQO/H4gI3XdiAij8M5Z2jmOmwjNBLA8' > "$root_password_hash"
chmod 600 "$root_password_hash"

AD5M_BUILDROOT_DIR="$buildroot_dir" AD5M_BUILD_OUT="$temp_output" \
    AD5M_ROOT_PASSWORD_HASH_FILE="$root_password_hash" \
    "$repo_root/build_scripts/build.sh" prepare_variant lite

config="$temp_output/buildroot/variant-lite/.config"
[[ -f "$config" ]] || fail "lite preparation did not produce .config: $config"

expected_common=$(realpath -m "$repo_root/build_overlays/common")
expected_lite=$(realpath -m "$repo_root/build_overlays/variant-lite")
grep -Fqx "BR2_ROOTFS_OVERLAY=\"$expected_common $expected_lite\"" "$config" || \
    fail "generated lite config has an unexpected rootfs-overlay contract"
grep -Fqx 'BR2_PACKAGE_MOONRAKER=y' "$config" || \
    fail "generated lite config does not enable Moonraker"
grep -Fqx 'BR2_PACKAGE_USTREAMER=y' "$config" || \
    fail "generated lite config does not enable ustreamer"
! grep -Eq '^BR2_PACKAGE_FFMPEG=y$|^BR2_PACKAGE_X264=y$' "$config" || \
    fail "generated lite config must not include the retired FFmpeg/x264 timelapse stack"
grep -Fqx 'BR2_TARGET_ENABLE_ROOT_LOGIN=y' "$config" || \
    fail "generated lite config does not explicitly retain password login"
grep -Fqx 'BR2_TARGET_GENERIC_ROOT_PASSWD="$$5$$ad5mtestsalt$$agH/idcAiVhRGQO/H4gI3XdiAij8M5Z2jmOmwjNBLA8"' "$config" || \
    fail "generated lite config did not retain the supplied escaped SHA-256-crypt hash"
! grep -Fq 'BR2_TARGET_GENERIC_ROOT_PASSWD="klipper"' "$config" || \
    fail "generated lite config reintroduced the shared legacy root password"
pass "lite configuration contains reviewed overlay and service selections"

printf 'Buildroot configuration validation passed\n'
