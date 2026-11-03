# MariaDB Shell Workbench on a Debian server (multi-user)

One MariaDB Shell Workbench per Linux user, started on demand, behind a Keycloak login with an
authenticator app code for every login. For a server on Debian 13 or Ubuntu 24.04, arm64 or x86_64,
with a public DNS name; 4 GB of RAM hold about two working users (an IDE needs about 1.3 GB).
The Raspberry Pi OS setup (`../Raspberry-Pi-OS/`, one user) uses the base, Keycloak and REST
scripts of this folder.

```
browser -> nginx :443  <host>, webview.<host>        (Let's Encrypt)
             /sso/     -> Keycloak 127.0.0.1:8080       (podman, data in the local MariaDB)
             /oauth2/  -> oauth2-proxy 127.0.0.1:4180   (podman)
             /         -> auth_request: workbench-spawner (/run/mariadb-shell-workbench/spawner.sock)
                            asks oauth2-proxy who is logged in, creates the Linux account at the
                            first login, starts mariadb-shell-workbench@<user>, names the user
                       -> /run/mariadb-shell-workbench/<user>/theia.sock   (Theia as <user>)
```

## Files

| File | Installed as | What |
| --- | --- | --- |
| `setup-base.sh` | - | Swap, nginx, certbot, podman, MariaDB server, ripgrep, build tools, Node 24, MariaDB Shell (`/opt/mariadb-shell/<version>`) |
| `install-restd.sh` | - | MariaDB REST daemon from a release tarball (`/opt/mariadb-restd/<version>`), downloaded from the releases of `github.com/mariadb-corporation/rest-daemon` |
| `setup-restd-proxy.sh` | `/etc/nginx/sites-available/restd-proxy`, `/etc/mariadb-restd/proxy.conf` | The users' REST daemons behind nginx under a host of their own (see "REST daemons") |
| `setup-keycloak.sh` | - | Certificate for both names, Keycloak database, Keycloak, login theme (`keycloak-theme/`, on MariaDB Shell's `mariadb-mcp`), first nginx vhost |
| `keycloak.container` | `/etc/containers/systemd/` | Keycloak 26 under `/sso`, local cache (no cluster ports), 512 MB heap |
| `setup-keycloak-realm.sh` | - | Realm `workbench`: theme, password + authenticator app flow, client, group, users |
| `setup-workbench.sh` | - | Build in `/opt/mariadb-shell-workbench`, units, spawner, oauth2-proxy, full nginx vhost |
| `deploy-workbench.sh` | - | From the development machine: copy the tree and the MariaDB extensions, run `setup-workbench.sh` |
| `mariadb-shell-workbench@.service` | `/etc/systemd/system/` | One IDE per user: socket, sandbox, memory and CPU limits, `dev@mariadb` install |
| `workbench-spawner.py`, `.service` | `/usr/local/lib/mariadb-shell-workbench/`, `/etc/systemd/system/` | Login check, accounts, IDEs on demand, idle IDEs (no tab connected) stopped after 90 minutes |
| `oauth2-proxy.container` | `/etc/containers/systemd/` | Login against the realm, group `workbench-users` only |
| `nginx-workbench.conf` | `/etc/nginx/sites-available/workbench` | The vhost for both names |
| `keycloak-theme/mariadb-shell-workbench/` | `/etc/mariadb-shell-workbench/keycloak-themes/` | The login page's texts, on MariaDB Shell's `mariadb-mcp` theme |

Secrets live in `/etc/mariadb-shell-workbench/` (root, mode 600): Keycloak's database and bootstrap
admin passwords, the client secret, the initial passwords of the users the realm script created.
They never appear on a command line: other users on the server can read process lists.

## Setup

DNS: `<host>` and `webview.<host>` point to the server, and ports 80 and 443 reach it (Let's
Encrypt). Copy this folder to the server (`scp -r deploy/Debian root@<host>:workbench-setup`) and
run, as root there (or with sudo):

```sh
./setup-base.sh
./install-restd.sh mariadb-restd-<version>-linux-<arch>.tar.gz SHA256SUMS   # see the script's header
./setup-keycloak.sh <host>
./setup-keycloak-realm.sh <host> <user>...    # Keycloak users; Linux accounts follow at first login
./setup-restd-proxy.sh <rest-host>             # a sibling of <host>, with its own DNS name
```

`setup-keycloak.sh` takes the `mariadb-mcp` theme from the installed MariaDB Shell;
`MARIADB_MCP_THEME=<folder>` points it at a newer one (mariadb-shell-plugins'
`mcp_plugin/keycloak-theme/mariadb-mcp`). The REST daemon steps are optional.

From the development machine, with both MariaDB extensions unpacked in `plugins/`:

```sh
deploy/Debian/deploy-workbench.sh <host>              # --no-build when only scripts changed
SSH_TARGET=admin@<host> deploy/Debian/deploy-workbench.sh <host>   # a sudo user instead of root
```

**Shown inside a cloud console** (a userscript): the console's origin must be
allowed to frame the IDE and the login page. Set `FRAME_ANCESTORS` (space-separated origins) for
`setup-keycloak-realm.sh` and `deploy-workbench.sh` (or `setup-workbench.sh`) once; both keep it in
`/etc/mariadb-shell-workbench/frame-ancestors`:

```sh
FRAME_ANCESTORS="https://console.example.com" ./setup-keycloak-realm.sh <host>
FRAME_ANCESTORS="https://console.example.com" deploy/Debian/deploy-workbench.sh <host> --no-build
```

## REST daemons

The users' MariaDB REST daemons (set up from the IDE with MariaDB Shell's REST tools) are served
by nginx with a Let's Encrypt certificate of their own host, `<rest-host>`:
`https://<rest-host>:<port>/...` for public ports 8443-8462. A daemon listens on `127.0.0.1`
without TLS on its port + 10000; the tools do that by themselves when
`/etc/mariadb-restd/proxy.conf` names the host (MariaDB Shell's TLS proxy mode). Each port also
has a default server that rejects the TLS handshake, so no other name is answered there.

**`<rest-host>` must be outside the Workbench's cookie domain:** a sibling such as
`webapps.example.com` beside `workbench.example.com`, never `<host>` itself or a name below it
(oauth2-proxy's login cookie is set for `.<host>`). Nothing ties a daemon port to a Linux user:
any user can listen on a port whose daemon is stopped, and nginx then serves that under
`<rest-host>`'s name and certificate. Under the Workbench's name, browsers would send it the
login cookie, and a replayed cookie opens the victim's IDE. Sub-paths under `<host>` would be
worse (the IDE's own origin) and break MRS's root-relative links. The same squatting can still
impersonate another user's REST service under `<rest-host>`; it reaches no Workbench session.

## Isolation

- Each IDE runs as its user, with private `/tmp`, the other homes hidden, `NoNewPrivileges`, and
  `MemoryMax`/`CPUQuota`. Homes are mode 0700.
- Theia listens on a Unix socket (`THEIA_SOCKET`, patch in `patches/@theia+core+*.patch`), in a
  directory that is `<user>:www-data 2750`: only the user and nginx reach it. With TCP ports on
  the loopback, any user with a terminal could open another user's IDE and skip the login.
- The spawner socket is `root:www-data 0660`: only nginx can ask it to create accounts or start IDEs.
- A Keycloak user maps to a Linux account only under a valid name, and an existing account must be
  in group `workbench`, so `root` or `www-data` never map to a system account.
- SSH with keys only (`/etc/ssh/sshd_config.d/00-workbench.conf` from `setup-base.sh`; the
  first value sshd reads wins, so it overrides cloud-init's drop-in). Only where the account
  running `setup-base.sh` already logs in with a key; `SSH_KEYS_ONLY=no` leaves sshd alone.
- Accounts get user and group IDs from 10000 on: Keycloak's container runs as UID 1000 on the
  host, and an account with that ID could signal it. Node.js is unpacked with `--no-same-owner`
  (its tarball's files belong to 1001:1001, which would have made the account with that ID own
  `/usr/local/bin/node`).
- Sandboxes and REST daemons outlive the IDE: the spawner (every minute) and the IDE's `ExecStop`
  move them from the IDE's cgroup into scopes in `workbench-daemons-<user>.slice` (limits like an
  IDE's). A reboot still ends them, and nothing starts them again.

## Keycloak notes

- No email address anywhere: there is no mail server to verify one, and oauth2-proxy fails the
  login with a 500 on an unverified email in the token. The user profile asks for neither email
  nor names, the client's tokens carry no `email` scope, and oauth2-proxy uses the user name.
- Every login needs password and authenticator app code (flow `browser-otp`); Keycloak's default
  asks for a code only if the user has set one up.
- The bootstrap `admin` is temporary: replace it with a permanent admin with an authenticator app.
- A Keycloak restart clears `kcadm`'s login inside the container: log in again before `kcadm` calls.
