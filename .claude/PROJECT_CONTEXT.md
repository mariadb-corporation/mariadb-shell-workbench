# Project context: mariadb-shell-workbench

## Project

The MariaDB Shell Workbench (formerly "MariaDB Cloud Workbench" and "Cloud IDE"; repo, folder and
systemd unit `mariadb-shell-workbench`): a browser IDE built on Eclipse Theia that hosts two MariaDB
VS Code extensions: the MariaDB Shell extension (its `.vsix` comes from the separate
`vscode-extension` repository), which runs on the MariaDB Shell, and the MariaDB Shell Agent AI agent
(universal `.vsix` from the separate `mariadb-shell-agent` repository, a rebranded Qwen Code fork,
formerly MariaDB Code / `mariadb-code`; checked out next to this one as `../mariadb-shell-agent`).
It runs from a server of one's own behind nginx, oauth2-proxy and Keycloak: one IDE for one user on
a Raspberry Pi (`deploy/Raspberry-Pi-OS/`), or one IDE per Linux user on a Debian or Ubuntu server
(`deploy/Debian/`). It can be shown inside cloud vendor
consoles by userscripts, and also builds as a desktop app (Electron, `electron/`,
`npm run build:standalone`) with both extensions bundled.

**Installation-specific context** (particular hosts, their live configuration, the console
userscripts) is in `private/PROJECT_CONTEXT.md`, which is not in this repository. Read it too when
it exists; a fact that names a particular host, address, account or machine goes there, never here.

## Architecture / key decisions

- **Request path:** browser (vendor console iframe, or the IDE directly) → nginx (TLS for `<host>`
  and `webview.<host>`) → oauth2-proxy (`127.0.0.1:4180`, Keycloak realm `workbench`) → Theia
  (`127.0.0.1:3000` on the Pi, a Unix socket per user on the multi-user server) → MariaDB extension →
  `mariadb-shell -- mcp start-server --transport=stdio --gui`, started lazily when a MariaDB view
  first asks for its contents.
- **Built on the server, not cross-built:** native Node modules need the server's architecture
  (arm64 on a Pi); `deploy-workbench.sh` copies the tree and runs `npm ci`, `download:plugins` and the
  production build there.
- **The MariaDB Shell:** the extension finds `mariadb-shell` on the `PATH` or runs the official
  installer into `~/.local/share/mariadb-shell/<version>`; it needs a release with a build for the
  server's platform (`gh release list -R mariadb-corporation/mariadb-shell`). `setup-base.sh` installs
  a pinned release for all users.
- **One webview origin:** `THEIA_WEBVIEW_EXTERNAL_ENDPOINT=webview.{{hostname}}` instead of Theia's
  default `{{uuid}}.webview.{{hostname}}`, to avoid a wildcard DNS name and certificate. All webviews
  share an origin; acceptable with only the MariaDB and built-in extensions. Theia's warning about it is
  turned off (`warnOnPotentiallyInsecureHostPattern` in `package.json`).
- **Login everywhere, LAN included,** via oauth2-proxy with Keycloak (the IDE has a terminal). Its own
  realm, because its login page must be frameable by the vendor consoles. The realm's client is
  `mariadb-shell-workbench` (oauth2-proxy `--client-id`; its Audience mapper must name the same id).
- **Login theme `mariadb-shell-workbench`** (`deploy/Debian/keycloak-theme/`): a child of MariaDB
  Shell's `mariadb-mcp` theme (`parent=mariadb-mcp`) that only replaces the texts. New themes and
  changed messages need a Keycloak restart. Its id was `mariadb-ide` earlier; a realm still set to
  that id shows Keycloak's own login page.
- **A login lasts 15 h** (developer use, long-running database operations): the realm's SSO Session
  Idle and SSO Session Max are both 15 h, oauth2-proxy has `--cookie-expire=15h`. oauth2-proxy
  refreshes against Keycloak every hour (`--cookie-refresh=1h`, which also locks a disabled user out
  within the hour), so the idle timeout must stay above 1 h: Keycloak's default 30 minutes ended every
  session between two refreshes. `setup-keycloak-realm.sh` sets it on every run.
- **Side bars:** MariaDB Shell's container (`mariadb-view`) is first in the left activity bar, MariaDB
  Shell Agent's (`mariadb-shell-agent-sidebar`) first in the secondary (right) side bar above Outline,
  and both are revealed when there is no saved layout. `scripts/add-mariadb-shell-agent-extension.sh`
  moves MariaDB Shell Agent's container from `activitybar` to `secondarySidebar` in the unpacked
  manifest (Theia maps that key to the right side; local VS Code keeps the manifest); ranks and reveal
  are in the plugin-ext patch (`MARIADB_CONTAINER_RANKS`: MariaDB Shell and MariaDB Shell Agent 1,
  MariaDB Shell's Deployments container `mariadb-deployments` 2 and its Schema Management container
  `mariadb-msm` 3, below MariaDB Shell; every other plugin container last, so a new MariaDB container
  needs a rank here; `MARIADB_CONTAINERS`: the two revealed; `MARIADB_VIEWS_COLLAPSED`:
  Deployments expanded, Deployment Vendors collapsed, since Theia expands only the first view it adds
  to a container).
- **Third-party iframe constraints** (the IDE runs cross-site inside a console):
  - every embedding console origin must be in nginx's `Content-Security-Policy: frame-ancestors` and in
    the realm's CSP header (`FRAME_ANCESTORS` of the setup scripts);
  - cookies must be `SameSite=None; Secure`: oauth2-proxy's `_workbench_oauth2` (shared with the
    webview host) and Theia's `theia-connection-token`, which Theia sets `Strict` and nginx rewrites
    with `proxy_cookie_flags`;
  - `THEIA_HOSTS=<host>`: behind the proxy the WebSocket's Origin and Host differ, and Theia's
    same-origin check rejects the backend connection (403) without it.
- **Theia patches via patch-package** (`patches/`, applied by `postinstall`, documented in `README.md`):
  welcome content of extension tree views created with `canSelectMany`, `showCollapseAll` or
  drag and drop never followed context-key changes (lookup by `{ id }` vs. options-keyed widget); the
  same patch places and reveals the MariaDB view containers. The `@theia/core` patch widens the side
  panels' default (Theia: `initialSizeRatio` 0.191 of the window) to fixed widths, at most half the
  window: left 350 px, right 450 px for MariaDB Shell Agent's chat) and puts the MariaDB seal into the
  menu bar's empty icon slot (`.theia-icon`, a CSS mask with a data URI of
  `mariadb-shell-agent/mariadb/assets/seal-mono.svg`, its view box `0 0 316 355`, paths only; regenerate
  it when that asset changes, in both `node_modules` and `electron/node_modules`, then `npx patch-package @theia/core`). It also adds `THEIA_SOCKET`: the backend listens on that Unix socket
  instead of `--hostname`/`--port` (the multi-user server; a stale socket file is removed first; macOS
  limits socket paths to 104 characters). Not reported upstream: no Eclipse Contributor Agreement.
- **Theme:** default Light Modern / Dark Modern by `prefers-color-scheme`, evaluated when the IDE loads
  (Theia has no live `window.autoDetectColorScheme`); a theme picked by hand wins.
- **MariaDB Shell Agent extension:** the universal build (no node-pty; runs on Linux arm64) bundles the
  CLI and starts its daemon on the server's loopback with a random port and a bearer token. Its
  webview runs in the user's browser, which cannot reach that loopback, and Theia has no port
  forwarding: the extension detects a browser-based host (`vscode.env.uiKind` Web) and routes all
  webview requests to the daemon as messages through its extension host (patch `0003` in
  `mariadb-shell-agent`). No nginx route or open port for the daemon. Web Shell features with their
  own WebSockets (terminal, live browser, voice, local files) are therefore unavailable here. Model
  provider settings live in `~/.mariadb-shell-agent` of the IDE's OS user; one Theia instance means
  all logged-in users share them, the workspace and the OS account (the multi-user server gives each
  user an instance and an account of their own). MariaDB's `dev` Claude plugin (skills, `mariadb` MCP
  server, LSP for `.sql`, CLI-guard hook) is installed out of the box: `scripts/install-ai-plugins.sh`
  runs before every start (systemd `ExecStartPre`, npm `prestart`, `run-dev.sh`) and installs
  `https://github.com/mariadb/ai-plugins:dev` with the bundled CLI when it is missing or came from
  another source. MariaDB Shell Agent has no system-wide extensions folder, only
  `~/.mariadb-shell-agent/extensions` of the user. A GitHub install records its commit, so
  `cli.js extensions update dev` picks up new commits; a local-path install updates only when the
  version changes. LSP is on via `"mariadb-shell-agent.experimentalLsp": true` in
  `~/.theia/settings.json`. Search uses the system `rg` (apt `ripgrep`): the bundled arm64 ripgrep
  crashes on a Raspberry Pi's 16 KiB pages.
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

## Current state

- Single-user (Pi) and multi-user (Debian) deployments work end to end in a real Firefox, also
  framed inside cloud vendor consoles: Keycloak login in the iframe → Theia → MariaDB extension
  (Connections view lists, New Connection webview form renders). On the multi-user server: login with
  authenticator app, the Linux account created at the first login, an IDE per user; tested isolation
  (another user cannot reach an IDE socket, the spawner socket or a home).
- MariaDB Shell Agent: secondary side bar entry, onboarding and provider picker work; in a local Theia
  the workspace loads and chat works through the daemon bridge with no direct browser request to the
  daemon.
- REST daemons behind nginx on a REST host of their own work end to end in Firefox. The REST tools'
  TLS proxy mode is not in a MariaDB Shell release yet (next steps).
- `deploy/Raspberry-Pi-OS/` has never been run end to end on a fresh image.
- Desktop app builds and starts on macOS arm64 (`.dmg`/`.zip`, all 16 bundled extensions deploy);
  the MariaDB views in it have not been exercised yet. Linux and Windows targets are configured but
  never built (electron-builder builds for the platform it runs on).
- Open: switching the OS between light and dark while the IDE is open takes effect on the next reload.
- Open: Overview and MariaDB Shell Agent once stayed empty in a real Firefox: the backend answered 404
  for their `theia-resource/...` requests, so Firefox's service worker for `webview.<host>` did not
  intercept them (it had fetched `service-worker.js`). Cause not found; next time get the webview
  iframe's console errors and check `about:serviceworkers`.

## Files that matter

- `package.json` → Theia app: its `version` is the Workbench's, shown in Help → About (read by the
  backend at runtime); pinned Theia packages, Open VSX built-in extensions (`theiaPlugins`),
  frontend/backend config (theme, webview warning, default preferences such as
  `application.confirmExit: always`, which asks before the page unloads: back, other URL, reload,
  closing, and `security.workspace.trust.enabled: false`: every user has only their own workspace,
  and until the trust question is answered the MariaDB views stay hidden),
  `postinstall: patch-package`, `allowScripts`
  (npm 11 skips dependency install scripts not listed there; approvals are version-pinned, so a
  dependency upgrade needs `npm install-scripts approve <pkg>` again; `puppeteer` and `@theia/ffmpeg`
  are denied: test tooling and Electron-only; `electron/package.json` allows `@theia/ffmpeg`).
- `patches/@theia+plugin-ext+*.patch` → the tree-view welcome fix, MariaDB container ranks and reveal.
  Edited by hand: a line added or removed in one hunk shifts the `+` start line of every later hunk
  of that file; test with patch-package against a pristine `npm pack` of the Theia package.
- `patches/@theia+core+*.patch` → side panel default widths, menu bar seal, `THEIA_SOCKET`.
- `deploy/Debian/` → the multi-user server (Debian 13 / Ubuntu 24.04; `FRAME_ANCESTORS` for consoles,
  kept in `/etc/mariadb-shell-workbench/frame-ancestors`): setup scripts in order (`setup-base.sh`,
  `install-restd.sh`, `setup-keycloak.sh`, `setup-keycloak-realm.sh <host> <user>...`,
  `setup-restd-proxy.sh <rest-host>`), units, spawner, nginx and oauth2-proxy templates (`@HOST@`);
  `deploy-workbench.sh <host> [--no-build]` from the development machine (copies the tree and
  `plugins/mariadb.*`, builds in `/opt/mariadb-shell-workbench`, reinstalls units, nginx,
  oauth2-proxy). Secrets in `/etc/mariadb-shell-workbench/`.
- `deploy/Debian/keycloak-theme/mariadb-shell-workbench/` → login theme texts (child of `mariadb-mcp`,
  which `setup-keycloak.sh` takes from the installed MariaDB Shell or `MARIADB_MCP_THEME`).
- `deploy/Raspberry-Pi-OS/` → one IDE for one user on a fresh Raspberry Pi OS: Debian's base, Keycloak
  and realm scripts plus its own `setup-workbench.sh` (system unit as `<user>` on 127.0.0.1:3000,
  oauth2-proxy upstream, nginx with `/sso`); `deploy-workbench.sh` = Debian's with
  `SETUP=Raspberry-Pi-OS`.
- `scripts/add-mariadb-extension.sh` → unpacks the newest `.vsix` from `../vscode-extension` into
  `plugins/<publisher>.<name>`, removing earlier MariaDB Shell builds (keeps `mariadb.mariadb-shell-agent`).
- `scripts/add-mariadb-shell-agent-extension.sh` (`npm run plugin:mariadb-shell-agent`) → unpacks the newest
  `*-universal.vsix` from `../mariadb-shell-agent/mariadb/dist` (built there with
  `mariadb/build-vsix.sh universal`) into `plugins/mariadb.mariadb-shell-agent`.
- `scripts/install-ai-plugins.sh` → installs `dev@mariadb` from GitHub into MariaDB Shell Agent before each
  start, if missing.
- `scripts/run-dev.sh` → ad-hoc Theia start in a checkout (the service is the normal way).
- `electron/` + `scripts/build-standalone.sh` (`npm run build:standalone`) → the desktop app: the same
  Theia app with target `electron` in its own folder (own `node_modules`, lock file, `../patches`),
  packaged by electron-builder into `electron/dist/` with `plugins/` copied in; entry
  `electron/scripts/electron-main.js` sets `THEIA_DEFAULT_PLUGINS`. Theia versions and frontend
  config are kept in step with the root by hand; the version is the root's. Unsigned. Icon from
  `images/mariadb-shell-workbench-icon.svg`, rendered at build time by `electron/scripts/render-icons.mjs`
  (macOS variant with Apple's 824/1024 margin).
  `theia rebuild:electron` keeps the browser-ABI native modules in `electron/.browser_modules/`
  (ignored).
- `LICENSE` (GPLv2; the MariaDB Shell repositories' file, kept identical to theirs) and
  `THIRD-PARTY-NOTICES.txt`, generated by `scripts/generate-notices.mjs` (`npm run notices`, also run by
  `build:standalone`) from the production entries of both lock files, the extensions in `plugins/`
  and `licenses/` (texts for packages that ship none: Theia's notices and licenses, refetched from
  the Theia tag on upgrade; Lumino's; `licenses/npm/<name>@<version>` per package version, sources in
  `licenses/README.md`, so a version change of such a package needs its file again). The desktop
  app carries both plus Electron's `LICENSE` and `LICENSES.chromium.html` (dropped otherwise). MariaDB Shell Agent is
  Apache-2.0 (from Qwen Code): bundled as a separate extension, not part of the GPLv2 work.
- `private/` (ignored; a git repository of its own) → installation-specific configuration and notes,
  the console userscripts (`private/demos/`), `private/userscripts.conf`, and
  `private/PROJECT_CONTEXT.md`. Nothing host-specific goes into this repository.
- `tools/` → development-machine tooling, never deployed (the deploy scripts exclude it, and `private/`,
  `.claude/`, `electron/`): `firefox-control/` (agent-driven Firefox, gitignored profile with logins
  and Tampermonkey), `serve-userscripts.sh` (Tampermonkey install URLs for `private/demos/`; fills
  `IDE_URL` from `private/userscripts.conf`); `tools/README.md`.

## Next steps

1. Optional: a small Theia frontend contribution that follows `prefers-color-scheme` changes live.
2. Drop the plugin-ext patch once Theia fixes the welcome-widget lookup (check on each Theia upgrade).
3. MariaDB Shell Agent: bridge the Web Shell's WebSockets if the terminal or live-browser features are
   needed (`mariadb-shell-agent` work).
4. Once a MariaDB Shell release carries the REST tools' proxy mode, install it with `setup-base.sh`
   (pinned `MARIADB_SHELL_TAG`).
5. Sandboxes and REST daemons as systemd services of their own on the multi-user server (one per
   user and deployment, `Restart=on-failure`, started at boot), so web apps served from them
   survive reboots and crashes; today the spawner only moves them out of the IDE's cgroup. Needs
   MariaDB Shell (mariadb-shell-plugins' sandbox and REST tools) to start, stop and query them
   through systemd (for example a root helper, or user services with `loginctl enable-linger`)
   instead of its detached start scripts.
6. Multi-user server hardening before strangers use it: replace Keycloak's temporary bootstrap
   `admin` with a permanent admin with an authenticator app; optionally shorten the 30-day cache of
   Keycloak's theme files in nginx so theme changes reach browsers. Capacity: about 1.3 GiB per
   working user, so a 4 GB server holds about two (closed tabs keep their IDE for the 90-minute
   idle time); size the server for the expected users.
7. Desktop app: try the MariaDB views and MariaDB Shell Agent in it; build on Linux (AppImage,
   `.tar.gz`) and Windows; sign and notarize for macOS (needs an Apple Developer ID); consider asar
   with the native modules and `plugins/` unpacked (electron-builder warns that it is off).
8. Run `deploy/Raspberry-Pi-OS/` once on a fresh Raspberry Pi OS image.

## Gotchas / things not to repeat

- **Theia webviews and partitioned cookies cannot be tested in the Playwright Firefox build:** its
  service workers did not serve `theia-resource` requests (webviews blank) and it does not show
  partitioned cookies. Verify webviews and the iframe login in a real Firefox.
- **Views stuck on "Looking for MariaDB connections..."** with no `mariadb-shell` process on the
  server: a layout Theia saved while its backend connection was failing is restored on every load;
  F1 → Reset Workbench Layout (the same reset fixes activity bar icons swapped after plugin changes:
  Theia numbers view-container icon classes by load order and keeps the old numbers in the saved
  layout). Diagnose by reading `mariadb.connectionsView` from Theia's ContextKeyService and the
  `plugin-view-data` widget via `window.theia.container` before suspecting the extension.
- **socket.io 403s** (oauth2-proxy log): missing `THEIA_HOSTS`, or a tab holding a stale
  `theia-connection-token` from before a Theia restart — reload the tab.
- **oauth2-proxy 403 at `/oauth2/callback`, "CSRF cookie ... was not found"**: the Keycloak login
  page sat open longer than the CSRF cookie lives (15 minutes, `--cookie-csrf-expire`) before the
  user logged in. Open the IDE's URL again for a fresh login, not the old Keycloak page.
- **An SSH tunnel to the IDE's `localhost:3000` does not work** because of `THEIA_HOSTS` (endless
  spinner); test through the public host or add the host to `THEIA_HOSTS` temporarily.
- **oauth2-proxy collapses `//` in paths with a 301** (Go path cleaning). Harmless for webviews, whose
  `theia-resource/...` requests are answered by Theia's service worker, never by the backend; a 404 for
  them at the backend means the service worker did not handle the request.
- **Deploy pitfalls:** stop the Theia service before a full deploy (`npm ci` replaces `node_modules`);
  `rsync --delete` of `plugins/` once wiped the Open VSX plugins (now excluded). The old process may
  log SIGSEGV or exit 1 while stopping, the new one starts normally. A deploy replaces the server's
  `plugins/mariadb.*` with the local ones, so both MariaDB extensions must be unpacked locally first
  (on a fresh checkout a deploy would wipe them). Scripts-only changes need no build (`--no-build`).
  `deploy/Debian/deploy-workbench.sh` needs GNU rsync on the development machine (`--chown`):
  macOS ships openrsync, which rejects that option (`brew install rsync`).
- **A local Theia must be opened as `http://localhost:3000`:** on `127.0.0.1` the webview host becomes
  `<uuid>.webview.127.0.0.1`, the browser blocks the frames (`about:blank#blocked`) and webview views
  such as MariaDB Shell Agent stay empty with no error in the backend.
- **Testing webview-to-daemon traffic locally proves little:** a local browser reaches the daemon's
  loopback directly. Run Theia on `localhost` (webviews at `<uuid>.webview.localhost`), drive it with
  Playwright's Chrome channel (renders Theia webviews, unlike its Firefox build) and assert that the
  browser makes no direct request to the daemon port.
- **Over SSH, never `pkill -f <pattern>` with a pattern that also appears in the ssh command line** — it
  kills the remote shell itself. Use `[x]yz` patterns or PIDs.
- **Default side panel widths and positions apply only without a saved layout:** a browser that has
  one needs F1 → Reset Workbench Layout once.
- **MariaDB Shell Agent's provider setup** reopens with `/auth` in its chat ("Connect a Provider").
- **Theia side panel ranks:** a rank of 0 is ignored (`if (options.rank)`), and plugin view containers
  are registered as `workbench.view.extension.<id>`, not by the manifest id. A browser with a saved
  layout keeps the old positions until F1 → Reset Workbench Layout.
- **A local `theia build` writes `esbuild.mjs` and `gen-esbuild.*.mjs`** (gitignored).
- **Renaming the Keycloak client id breaks the login at once** until oauth2-proxy's `--client-id`
  (its quadlet, then `daemon-reload` and restart) and the Audience mapper follow; the secret stays.
- **Keycloak realm headers:** the CSP value goes in the Content-Security-Policy field, X-Frame-Options
  stays empty; swapped fields leave the default `frame-ancestors 'self'` and a blank iframe.
- **Keycloak serves theme files for 30 days** (`Cache-Control: max-age=2592000`) under a URL that
  changes only with the Keycloak version: after a theme change a browser keeps the old look until a
  hard reload (Cmd+Shift+R).
- **`kcadm` inside the Keycloak container forgets its login when Keycloak restarts:** run
  `config credentials` again before the next call.
- **nginx does not inherit `add_header` into a location that has its own:** a header meant for every
  response has to be repeated there (`location /` with `Set-Cookie` in `nginx-workbench.conf`).
- **MariaDB Shell's releases are all prereleases,** so GitHub's `releases/latest/download/` answers 404:
  pin the tag. Without a `mariadb-shell` on the `PATH`, the MariaDB Shell extension installs its own
  `MINIMUM_SHELL_VERSION` (`vscode-extension/src/shell/constants.ts`) into every user's home.
- **Starting a daemon in an SSH command without redirecting its output keeps the session open** (a
  restd `start.sh` uses a plain `&`); redirect or detach it.
- **Comparing IDE memory:** take anon + swap of the unit's cgroup (`memory.stat`,
  `MemorySwapCurrent`), never RSS or `MemoryCurrent` alone. An IDE capped by `MemoryHigh` shows a
  peak just above the cap, not its need, and under server-wide memory pressure the kernel swaps
  the idle IDE's pages, which makes it look smaller in RAM.
- **Desktop build (`electron/`):** the Electron target needs `@theia/ffmpeg`'s native addon; with its
  install script not allowed, `theia build` fails with "Cannot find module '../build/Debug/ffmpeg.node'"
  (allow it in `allowScripts`, then `npm rebuild @theia/ffmpeg`). electron-builder 26 rejects
  `mac.identity: "-"` (ad-hoc) when the keychain has no valid identity; `null` skips signing. Electron
  42 has no install script and downloads its binary on first use. After an icon change macOS may
  show the old icon from its cache (`killall Dock`).
- **License texts for `licenses/npm/`:** take them from the release tag or the shipped package's
  README; a repository's default branch can carry a newer license (Font Awesome 6/7 vs. 4.7).
