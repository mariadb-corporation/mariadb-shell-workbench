# Multi-user server and REST daemons

[Back to the index](../PROJECT_CONTEXT.md)

Part of the architecture: the multi-user server of `deploy/Debian/` and the REST daemons behind nginx.

- **Multi-user server (`deploy/Debian/`, details in its `README.md`):** IDEs started on demand, Linux
  accounts created at the first login, Keycloak inside the server, every login with password and
  authenticator app code.
  - nginx `auth_request` → `workbench-spawner` (Python, root, on `/run/mariadb-shell-workbench/spawner.sock`,
    `root:www-data 0660`) asks oauth2-proxy who is logged in, creates the account (home 0700,
    `~/workspace`, group `workbench`; an existing account must be in that group, so `root` never
    maps), starts `mariadb-shell-workbench@<user>.service` and answers `X-Workbench-User`; nginx proxies to
    `/run/mariadb-shell-workbench/<user>/theia.sock` (`<user>:www-data 2750`). TCP ports on the loopback
    would let any user with a terminal open another's IDE. The spawner answers only once the IDE
    accepts a connection on its socket: Theia leaves the socket file behind when it stops, and
    trusting the file sends a login after an idle stop to nginx's 503 page ("could not be
    started"). The unit's `ExecStopPost` removes the file; the connection check stays the test.
  - Idle stop (`WORKBENCH_IDLE_MINUTES=90` in `workbench-spawner.service`): no heartbeat or
    activity measure; every 60 s the spawner asks `ss` whether anything is connected to an IDE's
    `theia.sock`. An open tab holds Theia's socket.io WebSocket (pings every 25 s, nginx allows a
    day without traffic), so an IDE with a tab open is never stopped, however long an operation
    runs. The clock starts when the last tab disconnects (closed, or a sleeping laptop: dropped
    after about 45 s); 90 minutes cover a lunch break, and on wake socket.io reconnects to the
    same backend. A stop ends everything left in the IDE's cgroup (terminals, the MCP server and
    its operations). Independent of the 15 h login: an open WebSocket is checked only when it
    opens. Longer means a closed tab's IDE holds its memory (up to 1.5 GB) longer.
  - Sandboxes and REST daemons outlive the IDE (they may serve web apps on the REST host).
    MariaDB Shell's start scripts detach them (sandbox: a bash restart loop with `mariadbd`
    under it; `mariadb-restd` alone), but they stay in the IDE's cgroup, and systemd's stop
    (`KillMode=control-group`) ends the whole cgroup. `adopt_daemons()` in the spawner, run every
    minute and from the IDE unit's `ExecStop` (which systemd also runs when the IDE exits on its
    own), moves every `mariadbd`/`mariadb-restd` in the cgroup, with its orphaned shell parent,
    into a transient scope `workbench-daemon-<user>-<pid>.scope` (`busctl` StartTransientUnit with
    `PIDs`: `systemd-run --scope` can only start new processes) in
    `workbench-daemons-<user>.slice` (user name `systemd-escape`d, a `-` would nest slices),
    limits like an IDE's set with `systemctl set-property --runtime`. They keep the IDE's mount
    namespace (its private `/tmp` is deleted at the stop; the sandbox's tmpdir and socket are in
    its own folder). A reboot ends them and nothing restarts them (next steps).
  - Account IDs from 10000 (`useradd -K UID_MIN=...` in the spawner): Keycloak's container runs
    as host UID 1000, and an account with that ID could signal (kill) it. Node.js is unpacked
    with `--no-same-owner`: its tarball's files are 1001:1001, which root's tar keeps. SSH takes
    keys only (`sshd_config.d/00-workbench.conf` from `setup-base.sh`).
  - The template unit: `User=%i`, `NoNewPrivileges`, `PrivateTmp`, `ProtectHome=tmpfs` +
    `BindPaths=/home/%i`, `MemoryHigh=1536M`/`MemoryMax=2G`, `CPUQuota=150%`,
    `install-ai-plugins.sh` as `ExecStartPre`. With MariaDB Shell Agent loaded an IDE needs about
    1.2–1.4 GiB (MariaDB Shell Agent's four CLI processes alone 700–850 MiB); at 1G it swapped. The
    daemon scopes keep 1G/1536M (`DAEMON_LIMITS` in the spawner).
  - Keycloak 26 in podman under `/sso` (data in the local MariaDB, `KC_CACHE=local`: otherwise JGroups
    listens on all interfaces), realm `workbench`, login theme `mariadb-shell-workbench`. Its own browser flow
    `browser-otp` makes the code required (Keycloak's default asks only users who set one up).
    No email anywhere: no mail server verifies one and oauth2-proxy fails the callback (500) on an
    unverified email, so the client has no `email` default scope, oauth2-proxy requests
    `openid profile` with `--oidc-email-claim=preferred_username`, and the user profile requires no
    email or names. Secrets reach `kcadm` through stdin or the environment, never a command line.
  - MariaDB Shell and `mariadb-restd` for all users in `/opt/<name>/<version>`, linked in
    `/usr/local/bin` (MariaDB Shell's release pinned in `setup-base.sh`; `install-restd.sh` takes a
    release tarball of `mariadb-corporation/rest-daemon` and its `SHA256SUMS`).
  - Framed by a console: `frame-ancestors` for both host names (the webview host also allows the
    IDE's origin), `SameSite=None` for oauth2-proxy's cookie and `theia-connection-token`, the
    realm's CSP without X-Frame-Options.
- **REST daemons on a shared server: TLS terminated by nginx, under a host of their own**
  (`setup-restd-proxy.sh <rest-host>`). Chosen over a certificate path all users read (the site's
  key would let any user impersonate the site). A daemon listens on `127.0.0.1` without TLS on its
  public port + 10000; nginx serves public ports 8443–8462 with the REST host's certificate and
  rejects the TLS handshake for any other name there. MRS's response links are root-relative, so
  nothing is rewritten, and sub-paths under one host would break them. The REST host must be outside
  the Workbench's cookie domain (a security review found that any user can listen on a stopped
  daemon's port; under the Workbench's name or below it, browsers would send that content the login
  cookie). The tool side is the TLS proxy mode of mariadb-shell-plugins' REST tools
  (`restd.proxy()`), set for every user in `/etc/mariadb-restd/proxy.conf`
  (`MARIADB_RESTD_PROXY_*`): environment variables do not reach the MCP server, because the VS Code
  extension starts it through the MCP SDK's stdio client, which passes on only `HOME`, `LOGNAME`,
  `PATH`, `SHELL`, `TERM` and `USER`. The extension never knows the REST host: it opens the `url`
  MariaDB Shell reports per deployment (`restd.get_restd_status`, `restd.configure_restd`), in
  the REST Daemons view, the sandbox REST setup and the MRS views (`restdFor()` matches a row's
  server and metadata schema to a deployment). Only where no deployment matches does it fall back
  to its setting `mariadb.mrs.restDaemonUrl`, which on a shared server knows no REST host (could be
  preset in `package.json`, for one fixed port only).
