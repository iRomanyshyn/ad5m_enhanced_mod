#!/usr/bin/env bash
# Portable source-quality checks for the AD5M integration tree.  These checks
# intentionally need only Bash, find, grep, and Python 3; they create Python
# bytecode exclusively in a temporary directory.
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

[[ -d "$repo_root/tests" ]] || fail "missing tests directory: $repo_root/tests"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ad5m-host-lint.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

mapfile -d '' -t python_files < <(
    find "$repo_root/build_scripts" "$repo_root/build_overlays" \
        "$repo_root/device_files" "$repo_root/tests" \
        -path "$repo_root/build_scripts/components/moonraker_extensions" -prune -o \
        -type f -name '*.py' -print0
)
if ((${#python_files[@]})); then
    command -v python3 >/dev/null 2>&1 || fail "python3 is required to compile Python sources"
    PYTHONPYCACHEPREFIX="$tmp_dir/pycache" python3 -m py_compile "${python_files[@]}"
fi
pass "Python syntax compiled for ${#python_files[@]} active source files without repository bytecode"

mapfile -d '' -t test_sources < <(
    find "$repo_root/tests" -type f \( -name '*.sh' -o -name '*.py' \) -print0
)
for source_file in "${test_sources[@]}"; do
    if grep -nE '[[:blank:]]+$' "$source_file"; then
        fail "trailing whitespace in test source: $source_file"
    fi
    if [[ -s "$source_file" && $(tail -c 1 "$source_file" | od -An -t x1 | tr -d '[:space:]') != "0a" ]]; then
        fail "missing final newline in test source: $source_file"
    fi
done
pass "${#test_sources[@]} project-owned test sources have basic whitespace hygiene"

printf 'host lint passed\n'
