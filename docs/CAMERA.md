# Camera

Klipper Mod for the AD5M uses [ustreamer](https://github.com/pikvm/ustreamer) for camera streaming. Linux uvcvideo / MJPEG compatible cameras should be automatically detected when connected via USB.

If a camera is detected, ustreamer is available via HTTP at port 8080. Use the
printer's persistent mDNS name so a DHCP address change does not invalidate
the configuration: `http://ad5m-<suffix>.local:8080/stream` (or `/snapshot`).
The camera must be manually configured in Mainsail or Fluidd. This is a
separate local-LAN endpoint; it is not authenticated by a Moonraker login.
