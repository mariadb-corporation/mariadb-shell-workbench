# Deploying the MariaDB Shell Workbench

Two ways to run the browser IDE on a machine of your own, both behind nginx with Let's Encrypt and
a Keycloak login with an authenticator app code, everything on that one machine:

| Folder | For | IDEs |
| --- | --- | --- |
| [`Debian/`](Debian/README.md) | A server with Debian 13 or Ubuntu 24.04 (arm64 or x86_64) | One per Linux user, started at login, stopped when idle; accounts created at the first login |
| [`Raspberry-Pi-OS/`](Raspberry-Pi-OS/README.md) | A Raspberry Pi 4 or 5 with Raspberry Pi OS (64-bit) | One, for one Linux user; uses `Debian/`'s base, Keycloak and REST scripts |

Both build the app on the target (its native modules are built for the target's architecture), in
`/opt/mariadb-shell-workbench`, from a copy of this working tree that `deploy-workbench.sh` sends
from the development machine together with the locally unpacked MariaDB extensions
(`npm run plugin:mariadb`, `npm run plugin:mariadb-shell-agent`).

Settings and secrets of a setup live on the target, in `/etc/mariadb-shell-workbench/`. Notes and
configuration of particular installations belong in `private/` (ignored by git), not here.
