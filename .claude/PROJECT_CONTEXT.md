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

## Context files

| File | What is in it |
| --- | --- |
| [`context/architecture.md`](context/architecture.md) | Key decisions: request path, building on the server, the MariaDB Shell, the desktop app's bundled tools, release builds, webviews, login and Keycloak theme, side bars, iframe constraints, Theia patches, theme, MariaDB Shell Agent |
| [`context/multi-user-server.md`](context/multi-user-server.md) | The multi-user server of `deploy/Debian/` (spawner, idle stop, daemons outliving the IDE, accounts, units, Keycloak, installs, framing) and REST daemons behind nginx on a REST host of their own |
| [`context/files.md`](context/files.md) | The files that matter, path by path |
| [`context/gotchas.md`](context/gotchas.md) | Gotchas and things not to repeat |

Read this index first, then only the files the task touches. Current state and next steps stay here.

## Current state

- Single-user (Pi) and multi-user (Debian) deployments work end to end in a real Firefox, also
  framed inside cloud vendor consoles: Keycloak login in the iframe → Theia → MariaDB extension
  (Connections view lists, New Connection webview form renders). On the multi-user server: login with
  authenticator app, the Linux account created at the first login, an IDE per user; tested isolation
  (another user cannot reach an IDE socket, the spawner socket or a home).
- MariaDB Shell Agent: secondary side bar entry, onboarding and provider picker work; in a local Theia
  the workspace loads and chat works through the daemon bridge with no direct browser request to the
  daemon.
- REST daemons behind nginx on a REST host of their own work end to end in Firefox; the REST tools'
  TLS proxy mode is in MariaDB Shell from 26.11.
- `deploy/Raspberry-Pi-OS/` has never been run end to end on a fresh image.
- Desktop app: built in CI for macOS arm64/x64, Linux x64/arm64 and Windows x64/arm64 and published
  as GitHub pre-releases (`gh release list`). A local macOS arm64 build starts with the bundled
  shell and daemon first on the backend's PATH. On macOS, `install.sh` installs a release into
  `/Applications` and the unsigned app opens from there without a Gatekeeper prompt. The Linux and
  Windows packages have never been installed.
- Open: switching the OS between light and dark while the IDE is open takes effect on the next reload.
- Open: Overview and MariaDB Shell Agent once stayed empty in a real Firefox: the backend answered 404
  for their `theia-resource/...` requests, so Firefox's service worker for `webview.<host>` did not
  intercept them (it had fetched `service-worker.js`). Cause not found; next time get the webview
  iframe's console errors and check `about:serviceworkers`.

## Next steps

1. Optional: a small Theia frontend contribution that follows `prefers-color-scheme` changes live.
2. Drop the plugin-ext patch once Theia fixes the welcome-widget lookup (check on each Theia upgrade).
3. MariaDB Shell Agent: bridge the Web Shell's WebSockets if the terminal or live-browser features are
   needed (`mariadb-shell-agent` work).
4. Raise `setup-base.sh`'s default `MARIADB_SHELL_TAG` to a 26.11 release (it carries the REST tools'
   proxy mode, and the MariaDB Shell extension's `MINIMUM_SHELL_VERSION` is above the current
   default, so users would get the extension's own copy in their homes instead).
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
7. Desktop app: install and start the Linux and Windows packages; try the MariaDB views and MariaDB Shell
   Agent in it; an installer for Linux and Windows next to `install.sh`; sign and notarize for macOS
   (needs an Apple Developer ID) and sign for Windows, after which releases need not be
   pre-releases; consider asar with the native modules and `plugins/` unpacked.
8. Run `deploy/Raspberry-Pi-OS/` once on a fresh Raspberry Pi OS image.
