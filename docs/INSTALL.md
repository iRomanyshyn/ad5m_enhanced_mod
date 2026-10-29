
# Install

Klipper Mod for the AD5M is designed to be fully removable and not break any functions of the stock software. 

> [!CAUTION]
> *If you want to install this Klipper Mod to your AD5M (Pro) then be aware, that you risk to loose your warranty or damage the printer. Proceed at your own risk if you want to try this mod!*

## Installation

The mod uses the same installation mechanism as the stock software:
1) Download the latest `Adventurer5M-KlipperMod*.tgz` update file from the [Release](https://github.com/xblax/flashforge_ad5m_klipper_mod/releases) page onto a USB flash drive.
2) Plug in the drive before starting the printer
3) The base image does **not** automatically flash either MCU during install or boot. MCU work is a separate, recovery-gated operation.
4) Successful installation will be indicated on the display when finished

The mod installer currently requires that printers were updated to at least version 2.4.5 of the stock Flashforge firmware. Please check the release page for versions that are known to work.

After installation the printer will by default start the Klipper Mod system instead of the stock Flashforge software. It is still possible to start the stock software without uninstalling the mod, if needed. See section [Dual Boot](#dual-boot) below.

### Install on 5M Pro

The installation archives are identical to the regular 5M. They must be named `Adventurer5MPro-*.tgz`, otherwise the install files are not detected by the 5M Pro printers.

### Initial Network Setup

The mod is pre-configured for DHCP. On a fresh installation it generates and
persists a local hostname such as `ad5m-a1b2c3d4e5f60708`. After successful
installation, open `AD5M-ADDRESS.txt` on the same USB drive for ready-to-copy
browser, Moonraker/slicer, and camera URLs using that name. Those `.local`
addresses require mDNS support on the local network; the printer must boot
before they resolve.

If mDNS is unavailable on a client, use the router's DHCP lease view as a
fallback. Do not use arbitrary USB files to change the chroot: that legacy
root-overlay feature was removed. Network and Wi-Fi configuration needs a
separate owner-controlled workflow.

### Install Log File

During the installation process a log file `klipper_mod_install.log` is written to the USB drive. This log file is helpful to understand the reason for installation failures. Please provide this file if you ask for help in the [GitHub Discussion](https://github.com/xblax/flashforge_ad5m_klipper_mod/discussions) forums.

## Updating

Updating the mod works similar to the installation. Be aware that that most local changes are lost during the update. Only a limited set of files is preserved while updating:

- Moonraker database
- G-Code files
- Network configuration and hostname
- Dropbear SSH Keys

To remove all persistent files, [Uninstall](UNINSTALL.md) the mod before re-installing.

> [!WARNING]
> If you have important files like custom printer configs make sure to create a backup before updating. Arbitrary USB root overlays are intentionally unsupported.

## Dual Boot

There are multiple options to boot the stock Flashforge software, while the mod is installed.

- USB drive: put a file named `klipper_mod_skip` on a USB drive and plug it in before printer start
- SSH: log in via SSH and run the command `reboot-stock-system` to restart and boot the stock software
- Klipper Macro: Execute the Klipper macro `REBOOT_STOCK_SYSTEM`

The retained legacy stock-boot/uninstall recovery path has not yet received
board-specific recovery validation. The base image no longer automatically
updates MCUs when starting Klipper Mod.
