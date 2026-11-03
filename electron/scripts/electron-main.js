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

// From the repository (npm start) macOS shows the Dock icon of node_modules' Electron.app; the
// packaged app gets its icon from electron-builder. Use the rendered one (npm run icons) instead.
const { app } = require('electron');
const devIcon = path.resolve(__dirname, '..', 'resources', 'icon-mac.png');
if (!app.isPackaged && process.platform === 'darwin' && fs.existsSync(devIcon)) {
    app.whenReady().then(() => app.dock.setIcon(devIcon));
}

require('../lib/backend/electron-main.js');
