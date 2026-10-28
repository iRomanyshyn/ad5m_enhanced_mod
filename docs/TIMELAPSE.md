# Timelapse (not included in the base image)

The AD5M base image deliberately excludes automatic timelapse capture,
rendering, FFmpeg, x264, and the Moonraker timelapse component. Rendering
during a print competes with motion control and is not a useful default on a
128 MiB printer.

The former component and macro sources are retained only as frozen provenance
references; they are not copied into the target rootfs and no configuration
activates them. A
future optional media add-on must have an explicit resource policy, manifest,
integrity verification, rollback path, and hardware validation before this
document becomes an installation guide again.
