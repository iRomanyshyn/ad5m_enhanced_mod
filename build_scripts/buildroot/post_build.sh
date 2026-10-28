#!/bin/bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "$SCRIPT_DIR/../env.sh"

BUILD_DIR_NAME="$(basename "$BASE_DIR")"

if [[ "$BUILD_DIR_NAME" =~ ^variant-(.+)$ ]]; then

    rest="${BASH_REMATCH[1]}"

    IFS='-' read -r -a parts <<< "$rest"

    BUILD_VARIANT="${parts[0]}"

    if [ "${#parts[@]}" -gt 1 ]; then
        BUILD_PLUGINS=( "${parts[@]:1}" )
    else
        BUILD_PLUGINS=()
    fi
fi

# Paths
TARGET_ROOT="$TARGET_DIR"

log_info "Deactivating 'S35iptables' initscript (if exists)."
chmod -x "$TARGET_ROOT/etc/init.d/S35iptables" || true

log_info "Cleaning up old build artifacts."
rm -rf "$TARGET_ROOT/root/printer_data/"

log_info "Recording the current UTC build time into fake-hwclock"
date -u '+%Y-%m-%d %H:%M:%S' > "$TARGET_ROOT/etc/fake-hwclock.data"

pushd "$GIT_ROOT" > /dev/null
KLIPPER_MOD_VERSION=$(git describe --tags --always --abbrev=7)
popd > /dev/null

cat << EOF > "$TARGET_ROOT/etc/os-release"
NAME=Buildroot-AD5M
VERSION=-$KLIPPER_MOD_VERSION
ID=buildroot
VERSION_ID=$KLIPPER_MOD_VERSION
PRETTY_NAME="Klipper Mod $KLIPPER_MOD_VERSION"
EOF

log_info "Installing custom Klipper Python extensions into /opt/klipper/klippy/extras/."
cp "$GIT_ROOT/build_scripts/components/klipper_extensions/"*.py "$TARGET_ROOT/opt/klipper/klippy/extras/" || true

# The base image intentionally ships no Moonraker extension.  In particular,
# do not copy the parked timelapse component: it would add an untested media
# workflow even when its configuration is absent.

log_info "Setting Moonraker API communication port to 7125 within Mainsail's configuration (/opt/mainsail/config.json). This ensures Mainsail can properly connect to Moonraker."
sed -i 's\"port": null\"port": 7125\g' "$TARGET_ROOT/opt/mainsail/config.json"

log_info "Initiating the copying process for essential printer configuration files."

mkdir -p "$TARGET_ROOT/root/printer_data/config"

log_info "  Copying all printer-specific configuration files from $GIT_ROOT/printer_configs/ to their final destination: /root/printer_data/config/."
cp -r "$GIT_ROOT/printer_configs/"* "$TARGET_ROOT/root/printer_data/config"
log_info "  Removing the retired timelapse macro from the base target configuration."
rm -f "$TARGET_ROOT/root/printer_data/config/timelapse.cfg"
log_info "Printer configurations successfully copied and staged for deployment."

log_info "Verifying and correcting D-Bus user and group entries in /etc/group, /etc/passwd, and /etc/shadow. This ensures D-Bus, a critical system message bus, operates securely."

# Checks if the 'dbus' group exists in /etc/group. If not, it adds the entry.
if ! grep -q dbus "$TARGET_ROOT/etc/group"; then
    log_warn "  'dbus' group not found in /etc/group. Adding entry for proper D-Bus functionality."
    echo "dbus:x:101:dbus" >> "$TARGET_ROOT/etc/group"
fi

# Checks if the 'dbus' user exists in /etc/passwd. If not, it adds the entry.
if ! grep -q dbus "$TARGET_ROOT/etc/passwd"; then
    log_warn "  'dbus' user not found in /etc/passwd. Adding entry for D-Bus messagebus user."
    echo "dbus:x:100:101:DBus messagebus user:/run/dbus:/bin/false" >> "$TARGET_ROOT/etc/passwd"
fi

# Checks if the 'dbus' user's shadow entry exists in /etc/shadow. If not, it adds a placeholder.
if ! grep -q dbus "$TARGET_ROOT/etc/shadow"; then
    log_warn "  'dbus' entry not found in /etc/shadow. Adding a placeholder entry for security consistency."
    echo "dbus:*:::::::" >> "$TARGET_ROOT/etc/shadow"
fi
log_info "D-Bus user and group configuration verified and any missing entries have been added."


for overlay in "$BUILD_OVERLAYS"/plugin-*; do
    plugin_name="${overlay##*/plugin-}"
    for target_plugin in "${BUILD_PLUGINS[@]}"; do
        if [[ "$target_plugin" == "$plugin_name" ]]; then
            log_info "Copying $plugin_name plugin overlay to rootfs."
            cp -a "$overlay"/. "$TARGET_ROOT/"
        fi
    done
done
