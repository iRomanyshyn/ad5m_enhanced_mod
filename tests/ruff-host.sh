#!/usr/bin/env bash
# Opt-in host-only Ruff check.  It intentionally does not install tooling or
# write a cache into the checkout.
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

[[ -f "$repo_root/ruff.toml" ]] || fail "missing Ruff configuration: $repo_root/ruff.toml"
command -v ruff >/dev/null 2>&1 || \
    fail "Ruff 0.17.0 is required; install the pinned host dependency from requirements-dev.txt"
[[ "$(ruff --version)" == "ruff 0.17.0" ]] || \
    fail "expected Ruff 0.17.0; found $(ruff --version)"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ad5m-ruff.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

runtime_sources=(
    "$repo_root/build_scripts/components/klipper_extensions/gcode_shell_command.py"
    "$repo_root/build_scripts/components/klipper_extensions/md5_checker.py"
    "$repo_root/build_scripts/components/klipper_extensions/power_loss_recovery.py"
    "$repo_root/build_scripts/components/moonraker_extensions/timelapse.py"
)

RUFF_CACHE_DIR="$tmp_dir/cache" ruff check --config "$repo_root/ruff.toml" "${runtime_sources[@]}"
pass "Ruff 0.17.0 found no unused runtime imports in ${#runtime_sources[@]} sources"
