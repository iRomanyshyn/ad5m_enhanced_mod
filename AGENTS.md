# AD5M Klipper Mod repository instructions

This repository owns Flashforge AD5M-specific Klipper Mod integration. It is
the fork `iRomanyshyn/ad5m_enhanced_mod`; its `upstream` remote is
`xblax/flashforge_ad5m_klipper_mod` and is a reference, not the project
coordination repository.

## Related repositories

- Project coordination: `../ad5m-project`
- Official-Buildroot-derived base: `../buildroot-flashforge-ad5m`

Before non-trivial work, read `../ad5m-project/PROJECT.md`, the applicable
task in `../ad5m-project/tasks/`, and the sibling Buildroot `AGENTS.md` when
ownership or build integration is involved.

## Ownership

Keep AD5M-specific configuration, macros, Moonraker and service integration,
installer/update logic, packaging, touchscreen/UI integration, Buildroot
external-tree configuration, and project-specific packages here. Generic
Buildroot fixes belong in `../buildroot-flashforge-ad5m` only after checking
the official 2025.02 LTS branch and newer official Buildroot for a suitable
fix.

The current `submodules/buildroot` relationship is historical build-system
coupling. Do not replace, initialize, or update it as incidental work; changes
to that relationship require a scoped coordination task.

## Safety and verification

Treat heaters, thermal verification, limits, homing, probing, Z movement,
load-cell behavior, MCU flashing, and power control as safety-critical. Never
weaken a safety mechanism merely to suppress an error. Clearly distinguish
configuration/build checks from physical-printer testing.

The printer is resource constrained. Prioritize Klipper/MCU communication and
avoid unnecessary daemons, RAM, CPU, disk writes, logging, or background work.

## Git rules

Inspect status and branch before editing. Do not commit, push, merge, rebase,
force-push, or open a pull request unless explicitly authorized. Do not commit
`build_output/`, secrets, or machine-specific files. Report files changed,
commands actually run, hardware testing still needed, and unresolved risks.
