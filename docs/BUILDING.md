# Building

The project is still pre-alpha; a successful build is not permission to
install it on a printer.  In particular, follow the recovery and hardware
readiness records in the project coordination repository before using an
artifact on real hardware.

## Per-printer root password input

The image intentionally has no committed default root password.  Before
preparing or building a variant, create a local per-printer password hash:

```sh
./build_scripts/create-root-password-hash.sh
```

The helper asks twice without echoing the password and stores only a
SHA-256-crypt hash at
`build_scripts/buildroot/configs/local/root-password.sha256`.  That directory
is ignored by Git and must remain private.  The password should be unique to
this printer; do not copy an old `root:klipper` convention or reuse a password
from another service.

For a deliberately managed local path, set
`AD5M_ROOT_PASSWORD_HASH_FILE=/protected/path/root-password.sha256` instead.
The file must contain exactly one raw `$5$...` SHA-256-crypt hash and have no
group or world permissions.  The build wrapper converts it to Buildroot's
escaped configuration form without retaining a clear-text password.

If the hash input is absent, malformed, or too broadly readable, preparing a
variant fails before Buildroot output is initialized.
