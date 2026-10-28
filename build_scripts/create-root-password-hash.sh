#!/usr/bin/env bash
# Create the ignored per-printer root-password input used by build.sh.
set -euo pipefail

if (( $# > 1 )); then
    printf 'usage: %s [output-file]\n' "$0" >&2
    exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
output_file=${1:-"$script_dir/buildroot/configs/local/root-password.sha256"}
output_dir=$(dirname -- "$output_file")

command -v openssl >/dev/null 2>&1 || {
    printf 'error: openssl is required to create a SHA-256-crypt password hash\n' >&2
    exit 1
}

if [[ -e "$output_file" ]]; then
    printf 'error: refusing to overwrite existing password hash: %s\n' "$output_file" >&2
    printf '       move it aside deliberately before creating a replacement.\n' >&2
    exit 1
fi

read -r -s -p 'New printer root password: ' password
printf '\n'
read -r -s -p 'Repeat printer root password: ' password_repeat
printf '\n'

if [[ -z "$password" ]]; then
    printf 'error: password must not be empty\n' >&2
    exit 1
fi
if [[ "$password" != "$password_repeat" ]]; then
    printf 'error: passwords do not match\n' >&2
    exit 1
fi
unset password_repeat

umask 077
mkdir -p "$output_dir"
chmod 700 "$output_dir"
password_hash=$(printf '%s' "$password" | openssl passwd -5 -stdin)
unset password

tmp_file=$(mktemp "$output_dir/.root-password.sha256.XXXXXX")
trap 'rm -f "$tmp_file"' EXIT
printf '%s\n' "$password_hash" > "$tmp_file"
chmod 600 "$tmp_file"
mv "$tmp_file" "$output_file"
trap - EXIT

printf 'Stored a local SHA-256-crypt password hash in %s\n' "$output_file"
printf 'It is ignored by Git. Keep it private and do not reuse this password across printers.\n'
