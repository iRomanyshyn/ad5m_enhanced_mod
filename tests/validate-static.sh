#!/usr/bin/env bash
# Static AD5M integration checks.  This script deliberately does not invoke
# Buildroot, initialise an output directory, or execute target-side code.
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

[[ -f "$repo_root/Makefile" ]] || fail "missing Makefile under $repo_root"
git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
    fail "not a Git worktree: $repo_root"

check_variant_declaration() {
    local makefile=$1
    local line variants

    line=$(grep -E '^[[:space:]]*VARIANTS[[:space:]]*[:?+]?=' "$makefile" || true)
    [[ -n "$line" ]] || return 1
    [[ "$line" != *$'\n'* ]] || return 1
    variants=${line#*=}
    read -r variants <<< "$variants"
    [[ "$variants" == "lite" ]]
}

check_host_init_usb_script_policy() {
    local init_script=$1

    ! grep -nE \
        '(klipper_mod_debug|mod_debug\.sh|(^|[;[:space:]])(/bin/)?(sh|bash)[[:space:]]+/(mnt|media)/|(^|[;[:space:]])(\.|source)[[:space:]]+/(mnt|media)/)' \
        "$init_script" >/dev/null
}

check_installer_preflight_order() {
    local installer=$1
    local archive_check_line tar_check_line free_space_line destructive_line

    archive_check_line=$(grep -nF 'xz -t "$WORK_DIR/chroot.tar.xz"' "$installer" | \
        head -n1 | cut -d: -f1)
    tar_check_line=$(grep -nF 'tar -tf - > /dev/null' "$installer" | \
        head -n1 | cut -d: -f1)
    free_space_line=$(grep -nF 'FREE_SPACE=$(df /data' "$installer" | \
        head -n1 | cut -d: -f1)
    destructive_line=$(grep -nF 'rm -rf $CHROOT_DIR' "$installer" | \
        head -n1 | cut -d: -f1)

    [[ -n "$archive_check_line" && -n "$tar_check_line" && \
        -n "$free_space_line" && -n "$destructive_line" ]] || \
        return 1
    (( archive_check_line < destructive_line && tar_check_line < destructive_line && \
        free_space_line < destructive_line ))
}

check_loadcell_diagnostic_patch() {
    local patch=$1

    grep -Fq 'Subject: [PATCH] Remove unsafe loadcell raw diagnostic' "$patch" &&
        grep -Fq '+  if (cmd_len > sizeof(slot->cmd_data)) {' "$patch" &&
        grep -Fq -- '-            "FLASHFORGE_LOAD_CELL_TEST",' "$patch" &&
        grep -Fq -- '-DECL_COMMAND(command_flashforge_loadcell_test_cmd,' "$patch"
}

check_ntp_default_policy() {
    local init_script=$1 config=$2

    grep -Fq 'NTP_CONFIG="/etc/default/ad5m-ntp"' "$init_script" &&
        grep -Fq 'if [ "$NTP_ENABLED" != "1" ]; then' "$init_script" &&
        grep -Fq 'NTP_ENABLED=0' "$config" &&
        grep -Fq 'NTP_SERVER=' "$config" &&
        ! grep -Eqi '(pool\.ntp\.org|[0-9]+\.pool\.ntp\.org)' "$init_script" "$config"
}

check_variant_declaration "$repo_root/Makefile" || \
    fail "supported variants must be exactly 'lite'"
pass "Makefile declares lite as the sole variant"

help_output=$(make -C "$repo_root" --no-print-directory help)
help_variants=""
while IFS= read -r line; do
    if [[ "$line" == "AVAILABLE VARIANTS:" ]]; then
        IFS= read -r help_variants || true
        break
    fi
done <<< "$help_output"
help_variants=${help_variants//[[:space:]]/}
[[ "$help_variants" == "lite" ]] || \
    fail "make help did not expose only lite (got: ${help_variants:-nothing})"
pass "make help exposes only lite"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ad5m-static-validation.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

for target in guppyscreen klipperscreen; do
    target_output="$tmp_dir/$target.out"
    if make -C "$repo_root" --no-print-directory -n "$target" >"$target_output" 2>&1; then
        fail "retired target '$target' unexpectedly exists"
    fi
    grep -Fq "No rule to make target '$target'" "$target_output" || \
        fail "retired target '$target' failed for an unexpected reason"
    pass "retired target '$target' is unavailable"
done

fixture="$repo_root/tests/fixtures/legacy-ui/Makefile"
[[ -f "$fixture" ]] || fail "missing negative fixture: $fixture"
if check_variant_declaration "$fixture"; then
    fail "negative legacy-UI fixture unexpectedly passed"
fi
pass "negative legacy-UI fixture is rejected"

[[ ! -e "$repo_root/.gitmodules" ]] || \
    fail "legacy Buildroot submodule metadata must not return"
if git -C "$repo_root" submodule status | grep -q .; then
    fail "unexpected Git submodule registration"
fi
pass "no legacy Buildroot submodule metadata"

production_paths=(
    Makefile
    README.md
    build_scripts
    build_overlays
    device_files
    docs
    printer_configs
)
for path in "${production_paths[@]}"; do
    [[ -e "$repo_root/$path" ]] || continue
    matches=$(find "$repo_root/$path" -type f -exec \
        grep -nI -E 'guppyscreen|klipperscreen|loss-and-quick' {} + 2>/dev/null || true)
    [[ -z "$matches" ]] || fail "forbidden legacy reference in active source:\n$matches"
done
pass "active source has no legacy-screen or legacy-Buildroot reference"

host_init="$repo_root/build_overlays/common/etc/init/S00klipper_mod"
[[ -f "$host_init" ]] || fail "missing host init script: $host_init"
if ! check_host_init_usb_script_policy "$host_init"; then
    fail "host init must not execute a USB-provided script"
fi
pass "host init does not execute USB-provided scripts"

usb_script_fixture="$tmp_dir/S00klipper_mod-usb-script"
printf '%s\n' '/bin/sh /mnt/mod_debug.sh' > "$usb_script_fixture"
if check_host_init_usb_script_policy "$usb_script_fixture"; then
    fail "USB-script execution negative fixture unexpectedly passed"
fi
pass "USB-script execution negative fixture is rejected"

installer="$repo_root/device_files/install/flashforge_init.sh"
[[ -f "$installer" ]] || fail "missing installer: $installer"
if ! check_installer_preflight_order "$installer"; then
    fail "installer must validate its archive and free space before deleting a chroot"
fi
pass "installer preflight precedes destructive chroot replacement"

loadcell_patch="$repo_root/build_scripts/buildroot/package/klipper/0004-Remove-unsafe-loadcell-raw-diagnostic.patch"
[[ -f "$loadcell_patch" ]] || fail "missing loadcell diagnostic safety patch"
if ! check_loadcell_diagnostic_patch "$loadcell_patch"; then
    fail "loadcell safety patch must remove raw G-code forwarding and bound MCU queue copies"
fi
pass "loadcell diagnostic raw command is removed and queue copy is bounded"

ntp_init="$repo_root/build_overlays/common/etc/init.d/S45ntpd"
ntp_config="$repo_root/build_overlays/common/etc/default/ad5m-ntp"
[[ -f "$ntp_init" && -f "$ntp_config" ]] || \
    fail "missing explicit NTP default-policy files"
if ! check_ntp_default_policy "$ntp_init" "$ntp_config"; then
    fail "NTP must be opt-in with no public default endpoint"
fi
pass "NTP is disabled by default and has no public default endpoint"

build_wrapper="$repo_root/build_scripts/build.sh"
[[ -f "$build_wrapper" ]] || fail "missing top-level build wrapper: $build_wrapper"
bash -n "$build_wrapper"
pass "top-level build wrapper has valid Bash syntax"

shell_roots=(build_scripts build_overlays device_files)
shell_count=1
while IFS= read -r -d '' file; do
    [[ "$file" == "$build_wrapper" ]] && continue
    IFS= read -r shebang < "$file" || true
    case "$shebang" in
        '#!'*'/bash'*|*'env bash'*)
            bash -n "$file"
            ;;
        '#!'*'/sh'*)
            sh -n "$file"
            ;;
        *)
            continue
            ;;
    esac
    shell_count=$((shell_count + 1))
done < <(find "${shell_roots[@]/#/$repo_root/}" -type f -print0)

[[ "$shell_count" -gt 0 ]] || fail "no shell scripts found to validate"
pass "shell syntax passed for $shell_count active scripts"

printf 'static validation passed\n'
