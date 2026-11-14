# Architecture / key decisions

[Back to the index](../PROJECT_CONTEXT.md)

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
- **The desktop app bundles MariaDB Shell and the REST daemon:** `scripts/fetch-bundled-tools.mjs`
  unpacks pinned releases (`MARIADB_SHELL_TAG`, `MARIADB_RESTD_TAG`) into `electron/bundle/<tool>`,
  which electron-builder copies to `app/bundle`. Only the packaged app (`app.isPackaged`) puts their
  `bin` folders first on the PATH (`electron/scripts/electron-main.js`); a development start keeps
  the developer's own builds. Theia's `fix-path` replaces `PATH` with the login shell's before it
  forks the backend, so `process.env` is wrapped in a `Proxy` that re-prepends the bundle folders
  on every PATH write. `MARIADB_SHELL_WORKBENCH_BUNDLED_TOOLS=0` turns it off. Nothing is installed
  into the user's home. The REST daemon has no Windows arm64 build; that package is built without it.
- **Release builds as MariaDB Shell's:** a push to `release/candidate` builds six platforms
  (`.github/workflows/release.yml`); Publish Release (`publish-release.yml`, by hand) turns a
  successful run into a GitHub pre-release with `SHA256SUMS`. CI takes both extensions from their
  GitHub releases (`MARIADB_EXTENSIONS_FROM=releases`, tags pinned in `scripts/fetch-extensions.mjs`);
  every pin is exact, and `/release` (`.claude/commands/release.md`) checks them against the
  published releases and the extension's `MINIMUM_SHELL_VERSION` / `MINIMUM_RESTD_VERSION`. Every
  release is a pre-release while the app is unsigned. `install.sh` installs a release on macOS.
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
  MariaDB Shell's Schema Management container `mariadb-msm` 2 and its Deployments container
  `mariadb-deployments` 3, below MariaDB Shell; every other plugin container last, so a new MariaDB container
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
