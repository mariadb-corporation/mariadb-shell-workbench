# Gotchas / things not to repeat

[Back to the index](../PROJECT_CONTEXT.md)

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
- **Desktop builds on CI runners:** electron-builder with `--publish never` still reads the publish
  config and crashes on its `null` channel unless `build.publish` is `null`. Its own node-gyp fork
  (`@electron/node-gyp` 10.2.0-electron.1), which runs dependency install scripts such as
  `drivelist`'s, does not know Visual Studio 2026 (the only one on `windows-11-arm`) and fails in
  `llvm-lib` with Node 24's ClangCL on `windows-2022`: overridden with node-gyp 12. On Windows,
  Git Bash's GNU tar reads neither `.zip` nor `C:\` paths; the fetch script calls
  `%SystemRoot%\System32\tar.exe` (bsdtar). Ubuntu 22.04 runners keep the Linux packages on glibc
  2.35, near the bundled shell's 2.34.
- **Release tags can only be created by admins** (ruleset "Create Release" on `refs/tags/v*`:
  creation, update, deletion): Publish Release's token gets `Cannot create ref due to creations
  being restricted`, so the annotated tag is pushed from an admin account first. Never `git push
  --tags` (local `archive/*` tags must stay private).
- **The MCP SDK's stdio transport passes only a few default variables to the server it starts:**
  `MARIADB_SHELL_*` set in a login shell (`MARIADB_SHELL_PLUGINS_PATH` for development plugins) did
  not reach `mariadb-shell` until the MariaDB Shell extension passed them on itself; "There is no
  object registered under name 'mcp'" means a shell without its plugins.
- **GUI apps started from a Claude Code session** need the command sandbox off, or they exit
  silently. Even with it off, the desktop app (local build and release alike) can quit at once with
  Electron's `codesign_util.cc ... task_name_for_pid: (os/kern) failure (5)` and no window, while
  the same app opens normally from Finder: a launch check of the desktop app is done by hand.
- **License texts for `licenses/npm/`:** take them from the release tag or the shipped package's
  README; a repository's default branch can carry a newer license (Font Awesome 6/7 vs. 4.7).
