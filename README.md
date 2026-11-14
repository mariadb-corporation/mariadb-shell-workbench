# MariaDB Shell Workbench

A browser IDE built on [Eclipse Theia](https://theia-ide.org/) 1.76 that hosts the MariaDB VS Code
extension (`../vscode-extension`), which runs on the MariaDB Shell, and the MariaDB Shell Agent
extension (`../mariadb-shell-agent`). It runs in the browser from a server of your own
(`deploy/`), can be shown inside cloud consoles by userscripts, and builds as a desktop
app (`electron/`).

## Layout

| Path | What |
| --- | --- |
| `package.json` | The Theia browser application: Theia packages, built-in VS Code extensions from Open VSX (`theiaPlugins`) |
| `scripts/add-mariadb-extension.sh` | Unpacks the MariaDB extension `.vsix` into `plugins/` |
| `scripts/install-ai-plugins.sh` | Installs MariaDB's `dev` plugin from `github.com/mariadb/ai-plugins` into MariaDB Shell Agent before each start, if missing |
| `deploy/Debian/` | A Debian or Ubuntu server: one IDE per Linux user on demand, Keycloak with authenticator app ([deploy/Debian/README.md](deploy/Debian/README.md)) |
| `deploy/Raspberry-Pi-OS/` | A Raspberry Pi: one IDE for one user, Keycloak with authenticator app ([deploy/Raspberry-Pi-OS/README.md](deploy/Raspberry-Pi-OS/README.md)) |
| `scripts/run-dev.sh` | Starts (or restarts) the app from a checkout on `127.0.0.1:3000`, log in `theia.log` |
| `tools/` | Development-machine tooling: a controllable Firefox, the userscript server ([tools/README.md](tools/README.md)) |
| `private/` | Not in this repository (ignored): notes and configuration of particular installations, the console userscripts (`private/demos/`) |
| `images/` | The Workbench app icon (SVG) |
| `LICENSE`, `THIRD-PARTY-NOTICES.txt` | GPLv2 (the MariaDB Shell repositories' LICENSE) and the shipped third-party components |
| `scripts/generate-notices.mjs` | Regenerates `THIRD-PARTY-NOTICES.txt` (`npm run notices`) |
| `licenses/` | License files of components whose packages ship none (Eclipse Theia) |
| `electron/` | The same Theia app with the Electron target: the desktop app (see "Desktop app" below) |
| `scripts/build-standalone.sh` | Builds the desktop app into `electron/dist/` (`npm run build:standalone`) |
| `scripts/start-standalone.sh` | Builds the desktop app and starts it from the tree, unpackaged (`npm run start:standalone`) |
| `patches/` | patch-package patches to Theia, applied by `postinstall` (see below) |
| `plugins/` | Unpacked VS Code extensions (generated, not committed) |

## Getting started

Everything below runs on macOS or Linux and starts from an empty folder. The Workbench and the
MariaDB extensions are checkouts side by side:

```
<folder>/
  mariadb-shell-workbench/   this repository
  vscode-extension/          the MariaDB Shell extension
  mariadb-shell-agent/       the MariaDB Shell Agent extension (optional, see below)
```

**MariaDB Shell Agent is optional for now:** its repository is not public yet. Without it the
Workbench builds and runs with the MariaDB Shell extension alone; skip the MariaDB Shell Agent steps
below (`build:standalone` and `npm start` only print a note that it is missing).

### 1. Prerequisites

- **Node.js 24.15 or newer** (`engines` in `package.json`), with npm 11.
- **A C/C++ toolchain and Python 3** for Theia's native modules (`node-pty`, `keytar`,
  `native-keymap`, `drivelist`): on macOS the Xcode Command Line Tools (`xcode-select --install`); on
  Debian or Ubuntu `build-essential python3 pkg-config libx11-dev libxkbfile-dev libsecret-1-dev`.
- **MariaDB Shell 26.10.2 or newer**, for the MariaDB views (26.10.3 or newer on Linux arm64, the
  first with a `linux-glibc2.34-arm-64bit` build). The extension finds `mariadb-shell` on the `PATH`
  or installs it itself.

### 2. Build the extensions

Each extension is built in its own repository into a `.vsix` file, which this repository unpacks
into `plugins/`. See their READMEs for details.

```sh
cd vscode-extension                    # github.com/mariadb-corporation/vscode-extension
npm install
npm run package                        # vscode-extension/*.vsix
cd ..

cd mariadb-shell-agent                 # optional, once its repository is available
corepack pnpm install --frozen-lockfile
mariadb/build-vsix.sh universal        # mariadb/dist/mariadb-shell-agent-<version>-universal.vsix
cd ..
```

The universal build of MariaDB Shell Agent runs on every platform, the Linux arm64 of a Raspberry Pi
included. After a new `.vsix`, repeat step 3's last two commands.

### 3. Install the Workbench and unpack the extensions

```sh
cd mariadb-shell-workbench
npm ci                                 # Theia and its tools; postinstall applies patches/
npm run download:plugins               # the built-in VS Code extensions from Open VSX
npm run plugin:mariadb                 # the newest vscode-extension/*.vsix
npm run plugin:mariadb-shell-agent     # optional: the newest universal MariaDB Shell Agent .vsix
```

### 4a. Run the browser app

```sh
npm run build                          # or build:dev: faster, unminified
npm start                              # http://localhost:3000
```

Open it as `http://localhost:3000`, not `http://127.0.0.1:3000`: without
`THEIA_WEBVIEW_EXTERNAL_ENDPOINT`, webviews load from `<uuid>.webview.<hostname>`, which is a valid
loopback name for `localhost` but not for `127.0.0.1`, so the browser blocks the frames and webview
views (MariaDB Shell Agent, the New Connection form) stay empty. The local IDE has no login; it
listens on `127.0.0.1` only. On a Linux machine, `scripts/run-dev.sh` does the same in the background
(log in `theia.log`). Run `npm run build` again after a change to `package.json` or `patches/`; a new
extension in `plugins/` needs only a restart.

### 4b. Run or package the desktop app

```sh
npm run start:standalone               # build and open the app from the checkout
npm run build:standalone               # build the installable packages into electron/dist/
```

`start:standalone` is the one for trying a change: it installs `electron/`'s own dependencies when
needed, builds and opens the app, without packaging it. `build:standalone` produces a `.dmg` and
`.zip` on macOS, an AppImage and `.tar.gz` on Linux, an installer on Windows; with `-- --dir` only
the unpacked app. Both take the extensions from `plugins/`. More in "Desktop app" below.

### 4c. Run it on a server

A server builds the app itself (native modules) and is set up and updated with the scripts in
`deploy/` ([deploy/README.md](deploy/README.md)), after steps 2 and 3 on the development machine:

```sh
deploy/Debian/deploy-workbench.sh <host>     # or deploy/Raspberry-Pi-OS/deploy-workbench.sh <host> <user>
```

## npm scripts

The root `package.json`'s scripts, in VS Code's NPM Scripts view. `electron/package.json` has its own
(`build`, `rebuild`, `start`, `package`, `icons`), which `build:standalone` and `start:standalone`
run; they are hidden from that view (`.vscode/settings.json`).

| Script | What it does | When |
| --- | --- | --- |
| `postinstall` | Applies `patches/` to Theia (patch-package) | Runs by itself after `npm ci` / `npm install` |
| `download:plugins` | Downloads the built-in VS Code extensions listed in `theiaPlugins` from Open VSX into `plugins/` | Once, and after a change to `theiaPlugins` |
| `plugin:mariadb` | Unpacks the newest `.vsix` from `../vscode-extension` into `plugins/` (or the `.vsix` given after `--`) | After a new MariaDB Shell extension build |
| `plugin:mariadb-shell-agent` | Unpacks the newest universal `.vsix` from `../mariadb-shell-agent/mariadb/dist` into `plugins/` and moves its view to the right side bar | After a new MariaDB Shell Agent build (optional for now) |
| `build` | Builds the browser app, production mode | After `npm ci` and after changes to `package.json` or `patches/` |
| `build:dev` | The same in development mode: faster, unminified, with source maps | While working on the app |
| `prestart` | Installs MariaDB's `dev` plugin into MariaDB Shell Agent if missing (`scripts/install-ai-plugins.sh`) | Runs by itself before `start` |
| `start` | Starts the browser app on `http://localhost:3000` with the extensions in `plugins/` | To use the local browser IDE |
| `build:standalone` | Builds the desktop app and packages it into `electron/dist/` (`scripts/build-standalone.sh`) | To make installable packages |
| `start:standalone` | Builds the desktop app and starts it from the checkout (`scripts/start-standalone.sh`) | To try the desktop app |
| `notices` | Regenerates `THIRD-PARTY-NOTICES.txt` | After a dependency or extension change (see "License") |

## Troubleshooting

- **Views stay on "Looking for MariaDB connections..."** although the extension activated
  (MariaDB output channel) and no `mariadb-shell -- mcp start-server --transport=stdio` runs on
  the server: the browser restored a layout Theia saved while its backend connection was failing, and
  the extension's tree views never ask for their contents. F1 → **Reset Workbench Layout**.
- **socket.io requests answered with 403** (oauth2-proxy log: `journalctl -u oauth2-proxy`):
  either `THEIA_HOSTS` does not list the public host name (Theia's WebSocket origin check), or the
  tab carries a stale `theia-connection-token` from before a Theia restart. Reload the tab.

## Theia patches

- `@theia+plugin-ext+1.76.0.patch`: view welcome content of an extension tree view never follows
  context key changes when the view was created with `canSelectMany`, `showCollapseAll` or a drag
  and drop controller. `PluginViewRegistry.getTreeViewWelcomeWidget` looks the widget up with
  `{ id }`, but the widget manager keys it by all its creation options, so the lookup finds nothing.
  The patch looks it up by `id`. Symptom without it: the MariaDB Connections view stays on
  "Looking for MariaDB connections..." although the extension set `mariadb.connectionsView`.
  Still present on Theia master (2026-10-22); drop the patch once fixed upstream.
  The same patch places the MariaDB view containers (`MARIADB_CONTAINERS` in
  `plugin-view-registry.js`): MariaDB Shell first in the activity bar (above Explorer) and MariaDB
  Shell Agent first in the secondary side bar (above Outline); MariaDB Shell's two other containers,
  Schema Management (`mariadb-msm`) and Deployments, follow MariaDB Shell in that order
  (`MARIADB_CONTAINER_RANKS`). Without a saved layout MariaDB Shell and MariaDB Shell Agent are revealed, so
  both side bars start expanded. Theia ids are `workbench.view.extension.<container id>`, and a rank
  of 0 is ignored (falsy). `scripts/add-mariadb-shell-agent-extension.sh` moves the MariaDB Shell Agent container
  from `activitybar` to `secondarySidebar` in the unpacked manifest (local VS Code keeps it left).
  Theia expands only the first view it adds to a container; `MARIADB_VIEWS_COLLAPSED` starts MariaDB
  Deployments' Deployments view expanded and Deployment Vendors collapsed.
  A browser with a saved layout needs F1 → Reset Workbench Layout once.
  It also keeps the metadata of a notebook an extension creates from data
  (`workspace.openNotebookDocument(type, data)`): `$tryCreateNotebook` in
  `notebook-documents-main.js` sends the metadata as a change event, but the plugin host takes a
  document metadata change from `$acceptModelChanged`'s fourth argument, which that call left out,
  so the extension saw `{}`. Symptom without it: a MariaDB Notebook opened from a connection tile
  on the Overview page has no connection. Drop it once fixed upstream.
  It also lets a tree view get its data widget when the view was hidden as its extension registered
  the tree data provider: `prepareView` puts a welcome placeholder into the view at load, and
  `initView` waits for `onDidExpandView` to replace it, but `tryFireOnDidExpandView` fired only for an
  empty view. The patch fires it as long as the view holds only placeholders (tree widgets without
  `model.proxy`). Symptom without it: such a view shows its welcome content, or nothing, for good.

- `@theia+core+1.76.0.patch`: fixed side panel widths instead of Theia's default (`initialSizeRatio`
  0.191 of the window width): left 350 px, right 450 px for MariaDB Shell Agent's chat (`initialSize`, a
  new option read by `SidePanelHandler.getDefaultPanelSize`, at most half the window). Only for layouts
  without a saved size; F1 → Reset Workbench Layout applies it to an existing one. Also the MariaDB seal in the
  menu bar's icon slot (`#theia:icon`, empty in Theia; margin `7px 5px 3px 8px`): a CSS mask in the title bar's text color with
  `mariadb-shell-agent/mariadb/assets/seal-mono.svg` (its view box `0 0 316 355`, paths only, URI-encoded); after a
  change of that asset, regenerate the data URI in `src/browser/style/index.css`.

## Desktop app

How to build and start it: "Getting started", step 4b. The packages are built for the platform the
build runs on (electron-builder); the build copies the extensions from `plugins/` into the app.

- `electron/package.json` is a second Theia app (target `electron`, its own `node_modules` and lock
  file) with the root's Theia packages plus `@theia/electron`, `electron` (the version
  `@theia/electron` asks for) and `electron-builder` (config in its `build` field). Keep its Theia
  versions and frontend config in step with the root `package.json`. Its version comes from the root
  at build time. `postinstall` applies `../patches`.
- `electron/scripts/electron-main.js` is the app's entry: it sets `THEIA_DEFAULT_PLUGINS` to the
  bundled extensions and adds `~/.mariadb-shell-workbench/plugins` for extensions added by hand.
- MariaDB Shell (with its plugins) and the MariaDB REST daemon are bundled, so the app needs no
  separate install: `build:standalone` runs `scripts/fetch-bundled-tools.mjs`, which takes the release
  archives for the build's platform (tags pinned there; `MARIADB_SHELL_TAG`, `MARIADB_RESTD_TAG`
  override them), checks them against the releases' `SHA256SUMS`, caches them in `.cache/releases/`
  and unpacks them into `electron/bundle/` (resources/app/bundle/ in the app, about 430 MB). The
  packaged app puts their `bin/` folders first on the `PATH`, where the extension looks for the shell
  and the shell for `mariadb-restd`. From the checkout (`start:standalone`, `npm start`) the `PATH` is
  left alone, so development builds on it are used; `MARIADB_SHELL_WORKBENCH_BUNDLED_TOOLS=0` does the
  same for a packaged app. The bundled shell sets the app's minimum OS: macOS 26 on Apple silicon,
  macOS 15 on Intel, glibc 2.34 on Linux. The REST daemon has no Windows arm64 build.
- `MARIADB_EXTENSIONS_FROM=releases npm run build:standalone` takes the two MariaDB extensions from
  their GitHub releases instead of `../vscode-extension` and `../mariadb-shell-agent`
  (`scripts/fetch-extensions.mjs`; `MARIADB_EXTENSION_TAG`, `MARIADB_SHELL_AGENT_TAG`), for builds
  without those checkouts, such as CI. `GITHUB_TOKEN` is sent with the downloads when set.
- Differences from the browser app: no `application.confirmExit: always` (a desktop window would ask
  at every quit), and `@theia/ffmpeg`'s install script is allowed (the Electron target needs it).
  `scripts/install-ai-plugins.sh` does not run; MariaDB Shell Agent installs plugins on its own.
- Not signed (no Apple Developer ID; `mac.identity` is `null`): a downloaded copy needs
  right-click → Open, or `xattr -dr com.apple.quarantine "MariaDB Shell Workbench.app"`.
- App icon: `images/mariadb-shell-workbench-icon.svg`, rendered at build time (`electron/scripts/render-icons.mjs`,
  resvg) into `electron/resources/` (not committed): `icon.png` full bleed for Linux and Windows,
  `icon-mac.png` with the art at 824 of 1024 px (Apple's icon grid) for macOS.
- `npm --prefix electron start` starts what was built last, without building; from a terminal inside
  VS Code it may need `ELECTRON_RUN_AS_NODE` unset (`start:standalone` does that).
- `electron/package.json` overrides `@electron/node-gyp` (electron-builder's old node-gyp fork, whose
  `node-gyp` would otherwise be the one dependency install scripts run) with node-gyp 12.4.0: the fork
  knows no Visual Studio 2026 and fails linking Node 24's ClangCL builds on Windows. electron-builder's
  own rebuild, the fork's only user, is off (`npmRebuild: false`); `theia rebuild:electron` already
  uses node-gyp 12.
- `"publish": null`: no update metadata (`latest.yml`); without it electron-builder fails on CI.

### Release builds

Like MariaDB Shell's: a push to `release/candidate` runs `.github/workflows/release.yml`
(Workbench-Release), which builds the desktop app on six runners (macOS arm64 and x64, Linux x64
and arm64 on Ubuntu 22.04, Windows x64 and arm64) with `MARIADB_EXTENSIONS_FROM=releases` and keeps
each platform's packages as an artifact of the run: `mariadb-shell-workbench-<version>-<os>-<arch>`
`.dmg`/`.zip` (macOS), `.AppImage`/`.tar.gz` (Linux; the x64 AppImage says `x86_64`), `.exe`
(Windows). A run takes about 30 minutes; the release tags of the shell, the REST daemon and both
extensions are the ones pinned in the fetch scripts.

`.github/workflows/publish-release.yml` (Publish Release, started by hand under Actions) turns a
successful run (the latest on `release/candidate` unless `run_id` is given) into a GitHub release
tagged `v<version>` (the root `package.json`'s version at that run's commit) on the commit the run
built, with the packages and a `SHA256SUMS`; prerelease by default, as the app is unsigned.
`dry_run` checks everything and prints the notes without creating the release.

## Behind a proxy, inside a console

- nginx with TLS in front, oauth2-proxy and Keycloak for the login, required everywhere (the IDE
  has a terminal): `deploy/`.
- Shown in a cloud console's iframe (a userscript): the console's origin must be allowed in nginx's
  `Content-Security-Policy: frame-ancestors` and in the realm's (`FRAME_ANCESTORS` in `deploy/`),
  and the cookies need `SameSite=None; Secure`, because Firefox partitions cookies of framed sites.
- Webviews: Theia's default is one origin per webview (`{{uuid}}.webview.{{hostname}}`), which
  needs a wildcard DNS name and certificate. We use one origin for all webviews instead:
  `THEIA_WEBVIEW_EXTERNAL_ENDPOINT=webview.{{hostname}}`, i.e. `webview.<host>`
  (one more DNS name and certificate SAN).

## License

MariaDB Shell Workbench is released under GPLv2 (`LICENSE`, the same file as in the MariaDB Shell
repositories). `THIRD-PARTY-NOTICES.txt` lists what it ships under other licenses: Eclipse Theia
(EPL-2.0 or GPL-2.0 with the Classpath exception; the changes in `patches/` are under Theia's terms),
the bundled extensions (each with its own license files in `plugins/`), and the npm packages of both
lock files with their license texts. Regenerate it with `npm run notices` after a dependency or
extension change and commit it; `build:standalone` regenerates it too and puts it into the desktop
app with `LICENSE`, Electron's `LICENSE` and `LICENSES.chromium.html`. On a Theia upgrade, fetch
`licenses/eclipse-theia-*` again from the new tag.
