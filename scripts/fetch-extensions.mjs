// Downloads the MariaDB Shell and MariaDB Shell Agent extensions from their GitHub releases and
// unpacks them into plugins/, for builds without the sibling checkouts (CI):
//
//   node scripts/fetch-extensions.mjs   (build-standalone.sh with MARIADB_EXTENSIONS_FROM=releases)
//
// Pinned by MARIADB_EXTENSION_TAG and MARIADB_SHELL_AGENT_TAG (release tags; the defaults below).
// Unpacking is left to add-mariadb-extension.sh and add-mariadb-shell-agent-extension.sh, which
// also take a local .vsix, so a release and a local build end up the same in plugins/.
import { spawnSync } from 'child_process';
import { join } from 'path';
import { releaseAsset, root } from './release-download.mjs';

const extensions = [
    {
        repo: 'mariadb-corporation/vscode-extension',
        tag: process.env.MARIADB_EXTENSION_TAG || 'v26.11.2',
        asset: version => `mariadb-shell-${version}.vsix`,
        unpack: 'add-mariadb-extension.sh',
    },
    {
        // The universal build has no node-pty and runs on every platform.
        repo: 'mariadb-corporation/mariadb-shell-agent',
        tag: process.env.MARIADB_SHELL_AGENT_TAG || 'v26.11.1',
        asset: version => `mariadb-shell-agent-${version}-universal.vsix`,
        unpack: 'add-mariadb-shell-agent-extension.sh',
    },
];

for (const extension of extensions) {
    const vsix = await releaseAsset(extension.repo, extension.tag, extension.asset(extension.tag.replace(/^v/, '')));
    const result = spawnSync('bash', [join('scripts', extension.unpack), vsix], { cwd: root, stdio: 'inherit' });
    if (result.status !== 0) {
        process.exit(result.status ?? 1);
    }
}
