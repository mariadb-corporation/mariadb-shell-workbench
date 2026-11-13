// Entry point of the desktop app: points Theia at the bundled VS Code extensions, then hands over to
// the generated Electron main (lib/backend/electron-main.js).
const fs = require('fs');
const os = require('os');
const path = require('path');

// Packaged: the extensions sit next to the app (electron-builder extraResources → app/plugins).
// From the repository (npm start): the Workbench's plugins/ one level up.
const builtIn = [path.resolve(__dirname, '..', 'plugins'), path.resolve(__dirname, '..', '..', 'plugins')]
    .find(dir => fs.existsSync(dir));
if (builtIn) {
    process.env.THEIA_DEFAULT_PLUGINS = `local-dir:${builtIn}`;
}
// Extensions the user adds by hand.
process.env.THEIA_PLUGINS = [process.env.THEIA_PLUGINS, `local-dir:${path.join(os.homedir(), '.mariadb-shell-workbench', 'plugins')}`]
    .filter(Boolean)
    .join(',');

const { app } = require('electron');

// Packaged: MariaDB Shell and the REST daemon bundled with the app (scripts/fetch-bundled-tools.mjs,
// extraResources → app/bundle) go first on the PATH, where the MariaDB extension looks for the shell
// and the shell for mariadb-restd; started from the Finder or the Dock the PATH has neither. From the
// repository (npm start) the PATH stays as it is, so development builds on it are used.
// MARIADB_SHELL_WORKBENCH_BUNDLED_TOOLS=0 does the same for a packaged app.
const bundle = path.resolve(__dirname, '..', 'bundle');
if (app.isPackaged && process.env.MARIADB_SHELL_WORKBENCH_BUNDLED_TOOLS !== '0') {
    const bins = ['mariadb-shell', 'mariadb-restd']
        .map(tool => path.join(bundle, tool, 'bin'))
        .filter(dir => fs.existsSync(dir));
    const withBundled = value => [...bins, ...(value ?? '').split(path.delimiter).filter(dir => dir && !bins.includes(dir))]
        .join(path.delimiter);
    // Windows spells it Path; Node's process.env ignores the case there.
    process.env.PATH = withBundled(process.env.PATH);
    // Theia's fix-path (in the generated main, compiled into its bundle) then replaces PATH with the
    // login shell's, where macOS's path_helper and the user's dotfiles put these folders last, and
    // the backend is forked with that environment. Every later PATH assignment keeps them first.
    process.env = new Proxy(process.env, {
        set(env, name, value) {
            env[name] = String(name).toUpperCase() === 'PATH' ? withBundled(value) : value;
            return true;
        },
    });
}

// From the repository (npm start) macOS shows the Dock icon of node_modules' Electron.app; the
// packaged app gets its icon from electron-builder. Use the rendered one (npm run icons) instead.
const devIcon = path.resolve(__dirname, '..', 'resources', 'icon-mac.png');
if (!app.isPackaged && process.platform === 'darwin' && fs.existsSync(devIcon)) {
    app.whenReady().then(() => app.dock.setIcon(devIcon));
}

require('../lib/backend/electron-main.js');
