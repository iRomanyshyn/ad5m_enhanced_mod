#!/bin/sh
# This script is called once during install after initial
# setup of the chroot (executed within the chroot)
set -x

# prepare swap
fallocate -l 128M /mnt/swap
mkswap /mnt/swap
chmod 0600 /mnt/swap

##############################
# static data setup
##############################

static_dir="/mnt/data/.klipper_mod/static"
mkdir -p $static_dir

# On a genuinely fresh installation, replace only the generic build-time
# hostname with a persistent random local name before it is moved into static
# state. Existing installations always retain their selected hostname.
if [ ! -e "$static_dir/etc/hostname" ] && \
   [ "$(tr -d '\r\n' < /etc/hostname)" = "AD5M" ]; then
  if device_name=$(/usr/libexec/ad5m-device-name generate); then
    printf '%s\n' "$device_name" > /etc/hostname
    echo "Generated persistent local hostname: $device_name"
  else
    # Do not replace a name with predictable data or abort after the legacy
    # installer has already changed its chroot. The generic name remains a
    # visible recovery state that the owner can rename later.
    echo "Warning: could not generate a unique hostname; retaining AD5M."
  fi
fi

setup_static_data()
{
  # initial static data is initialized from the chroot
  if [ ! -e "$static_dir/$1" ]; then
    mkdir -p "$static_dir/"$(dirname "$1")
    mv "$1" "$static_dir/$1"
  fi

  # symlink the target to the static data dir
  rm -rf "$1"
  ln -s "$static_dir$1" "$1"
}

# keep essential network settings
setup_static_data /etc/hostname
setup_static_data /var/lib/iwd
setup_static_data /etc/network/interfaces
setup_static_data /etc/wpa_supplicant.conf

# keep dropbear keys (that is a symlink to /var/run/dropbear originally)
rm -f /etc/dropbear
mkdir -p /etc/dropbear
setup_static_data /etc/dropbear
# keep /root/.ssh
mkdir -p /root/.ssh
chmod 700 /root/.ssh
setup_static_data /root/.ssh

# keep moonraker database
mkdir -p /root/printer_data/database
setup_static_data /root/printer_data/database
# keep gcode files
mkdir -p /root/printer_data/gcodes
setup_static_data /root/printer_data/gcodes

##############################
# install done
##############################

audio midi -m /usr/share/midis/getitem.mid &
exit 0
