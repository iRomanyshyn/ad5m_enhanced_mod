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

AD5M_BUILDROOT_DIR="$buildroot_dir" AD5M_BUILD_OUT="$temp_output" \
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
pass "lite configuration contains reviewed overlay and service selections"

printf 'Buildroot configuration validation passed\n'
