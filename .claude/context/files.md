# Files that matter

[Back to the index](../PROJECT_CONTEXT.md)

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
  (ignored). `electron/package.json` sets `publish: null`, `artifactName`
  (`mariadb-shell-workbench-<version>-<os>-<arch>.<ext>`; the x64 AppImage says `x86_64`) and the
  `@electron/node-gyp` → node-gyp 12 override (gotchas).
- `scripts/fetch-bundled-tools.mjs`, `scripts/fetch-extensions.mjs` (with
  `MARIADB_EXTENSIONS_FROM=releases`), `scripts/release-download.mjs` → the pinned release downloads
  of the desktop build, checked against each release's `SHA256SUMS`, cached in `.cache/releases/`
  (ignored), retried on dropped connections. `fetch-extensions.mjs` replaces `plugins/mariadb.*`:
  never run it in a development checkout whose extensions are local builds.
- `.github/workflows/release.yml` (Workbench-Release), `.github/workflows/publish-release.yml` and
  `.claude/commands/release.md` (`/release`) → the release process (Architecture).
- `install.sh` → macOS installer for a release (`MARIADB_SHELL_WORKBENCH_TAG` or `--pre-release`):
  the `.zip` for the CPU, checked against `SHA256SUMS`, swapped into `/Applications` (or
  `~/Applications`), `xattr -cr` so Gatekeeper accepts the unsigned app. The release notes carry its
  `curl … | bash` command.
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
