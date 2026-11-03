# MariaDB Shell Workbench on a Raspberry Pi (one user)

One MariaDB Shell Workbench for one Linux user on a Raspberry Pi 4 or 5 with Raspberry Pi OS
(64-bit, based on Debian 13), behind a Keycloak login with an authenticator app code, everything on
the Pi itself. Raspberry Pi OS is Debian: the base system, Keycloak, the realm and the REST daemon
proxy come from `../Debian/`; this folder adds the single-user IDE in place of Debian's per-user
IDEs and spawner.

```
browser -> nginx :443  <host>, webview.<host>        (Let's Encrypt)
             /sso/     -> Keycloak 127.0.0.1:8080       (podman, data in the local MariaDB)
             /         -> oauth2-proxy 127.0.0.1:4180   (podman, login, group workbench-users)
                       -> Theia 127.0.0.1:3000          (mariadb-shell-workbench.service, as <user>)
```

## Files

| File | Installed as | What |
| --- | --- | --- |
| `setup-workbench.sh` | - | Build in `/opt/mariadb-shell-workbench`, the IDE unit, oauth2-proxy, the nginx vhost |
| `deploy-workbench.sh` | - | From the development machine: copy the tree and the MariaDB extensions, run `setup-workbench.sh` |
| `mariadb-shell-workbench.service` | `/etc/systemd/system/` | The IDE as `<user>`, workspace `~/workspace`, `dev@mariadb` install |
| `oauth2-proxy.container` | `/etc/containers/systemd/` | Login against the realm, group `workbench-users` only, then Theia |
| `nginx-workbench.conf` | `/etc/nginx/sites-available/workbench` | The vhost for both names: Keycloak under `/sso`, the rest through oauth2-proxy |

Secrets live in `/etc/mariadb-shell-workbench/` (root, mode 600), as on Debian.

## Setup

1. Raspberry Pi OS Lite (64-bit) on the Pi, with Raspberry Pi Imager: set the user, and enable SSH
   with your public key (with a password only, `setup-base.sh` leaves password logins on).
2. DNS: `<host>` and `webview.<host>` point to the Pi, and ports 80 and 443 reach it (a router
   forwarding them, for Let's Encrypt and for logins from outside).
3. Copy `../Debian/` to the Pi and run, there:

   ```sh
   scp -r deploy/Debian <user>@<pi>:workbench-setup
   ssh <user>@<pi>
   cd workbench-setup
   sudo ./setup-base.sh
   sudo ./setup-keycloak.sh <host>
   sudo ./setup-keycloak-realm.sh <host> <login>...   # Keycloak logins; all of them get this one IDE
   ```

   The REST daemon steps of `../Debian/README.md` (`install-restd.sh`, `setup-restd-proxy.sh`)
   work here too and are optional.
4. From the development machine, with both MariaDB extensions unpacked in `plugins/`:

   ```sh
   deploy/Raspberry-Pi-OS/deploy-workbench.sh <host> <user>               # --no-build when only scripts changed
   SSH_TARGET=<user>@<pi> deploy/Raspberry-Pi-OS/deploy-workbench.sh <host> <user>   # reached under another name
   ```

   The first build takes a while on a Pi (`setup-base.sh` adds swap for it: 4 GB of heap).

Shown inside a cloud console: `FRAME_ANCESTORS`, as in `../Debian/README.md`.

## One user

- Every Keycloak login in group `workbench-users` gets the same IDE, as `<user>`: its terminal,
  files and `sudo`. Add only people who may have that account.
- Theia listens on `127.0.0.1:3000`, which every account on the Pi reaches without logging in; the
  Debian setup's per-user Unix sockets are for servers shared by several accounts.
- Logs: `journalctl -u mariadb-shell-workbench`, `journalctl -u oauth2-proxy`, `journalctl -u keycloak`.
