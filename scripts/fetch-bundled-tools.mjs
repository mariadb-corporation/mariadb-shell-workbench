// Puts the MariaDB Shell and REST daemon releases for the platform this runs on into
// electron/bundle/ (gitignored), which the desktop app ships as resources/app/bundle/:
//
//   node scripts/fetch-bundled-tools.mjs
//
// Pinned by MARIADB_SHELL_TAG and MARIADB_RESTD_TAG (release tags; the defaults below). Each
// archive is checked against its release's SHA256SUMS and cached in .cache/releases/. A tool that
// is already unpacked from the same archive is left alone. electron-builder builds for the platform
// it runs on, so each CI runner fetches its own platform's archives.
import { spawnSync } from 'child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from 'fs';
import { join, relative } from 'path';
import { releaseAsset, root } from './release-download.mjs';

const bundle = join(root, 'electron', 'bundle');
const exe = name => process.platform === 'win32' ? `${name}.exe` : name;

// The release archive names differ between the two repositories:
//   mariadb-shell-26.11.1-macos26-arm-64bit.tar.gz, ...-linux-glibc2.34-x86-64bit.tar.gz
//   mariadb-restd-26.11.0-macos-arm64.tar.gz, ...-linux-aarch64.tar.gz, ...-windows-x64.zip
// `variant` matches the OS or glibc version some names carry; of several matches the lowest wins
// (the build that runs on the most systems).
const tools = [
    {
        name: 'mariadb-shell',
        repo: 'mariadb-corporation/mariadb-shell',
        tag: process.env.MARIADB_SHELL_TAG || 'v26.11.1',
        os: { darwin: 'macos', linux: 'linux', win32: 'windows' },
        arch: { arm64: 'arm-64bit', x64: 'x86-64bit' },
        pattern: (version, os, arch) => new RegExp(`^mariadb-shell-${version}-${os}(?<variant>\\d*|-glibc[\\d.]+)-${arch}\\.tar\\.gz$`),
    },
    {
        name: 'mariadb-restd',
        repo: 'mariadb-corporation/rest-daemon',
        tag: process.env.MARIADB_RESTD_TAG || 'v26.11.0',
        os: { darwin: 'macos', linux: 'linux', win32: 'windows' },
        arch: process.platform === 'darwin' ? { arm64: 'arm64', x64: 'x86_64' }
            : process.platform === 'linux' ? { arm64: 'aarch64', x64: 'x86_64' }
            : { x64: 'x64' },
        pattern: (version, os, arch) => new RegExp(`^mariadb-restd-${version}-${os}(?<variant>)-${arch}\\.(tar\\.gz|zip)$`),
    },
];

const variantNumber = name => Number((name.match(/(\d+(\.\d+)?)/g) ?? []).pop() ?? 0);

async function fetchTool(tool) {
    const os = tool.os[process.platform];
    const arch = tool.arch[process.arch];
    const dest = join(bundle, tool.name);
    if (!os || !arch) {
        // Not fatal: without a bundled copy the extension and the shell install one when needed.
        console.warn(`warning: ${tool.name} has no build for ${process.platform} ${process.arch}; the app is built without it`);
        rmSync(dest, { recursive: true, force: true });
        return;
    }
    const version = tool.tag.replace(/^v/, '');
    const sums = readFileSync(await releaseAsset(tool.repo, tool.tag, 'SHA256SUMS'), 'utf8')
        .split('\n').map(line => line.trim().split(/\s+\*?/)).filter(([hash, name]) => hash && name);
    const pattern = tool.pattern(version.replace(/\./g, '\\.'), os, arch);
    const matches = sums.filter(([, name]) => pattern.test(name))
        .sort(([, a], [, b]) => variantNumber(a.match(pattern).groups.variant) - variantNumber(b.match(pattern).groups.variant));
    if (!matches.length) {
        throw new Error(`${tool.repo} ${tool.tag} has no archive for ${os} ${arch} (looked for ${pattern})`);
    }
    const [hash, name] = matches[0];

    const stamp = join(dest, '.bundle-source');
    if (existsSync(stamp) && readFileSync(stamp, 'utf8').trim() === `${name} ${hash}`) {
        console.log(`${tool.name}: ${name} already in ${relative(root, dest)}`);
        return;
    }
    const archive = await releaseAsset(tool.repo, tool.tag, name, hash);

    // Unpacked next to the target, then moved into place. tar is bsdtar on macOS and Windows and
    // unpacks the Windows .zip as well; on Windows it is named in full, since Git Bash puts its GNU
    // tar first on the PATH, which reads neither a .zip nor "C:\..." (a remote host to it).
    mkdirSync(bundle, { recursive: true });
    const tmp = mkdtempSync(join(bundle, `.${tool.name}-`));
    try {
        const tar = process.platform === 'win32' ? join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'tar.exe') : 'tar';
        const result = spawnSync(tar, ['-xf', relative(tmp, archive)], { cwd: tmp, stdio: 'inherit' });
        if (result.status !== 0) {
            throw new Error(`tar could not unpack ${name}`);
        }
        // The archives hold a single top-level folder named after the archive.
        const top = join(tmp, name.replace(/\.(tar\.gz|zip)$/, ''));
        const binary = join(top, 'bin', exe(tool.name));
        if (!existsSync(binary)) {
            throw new Error(`${name} has no bin/${exe(tool.name)} below its top-level folder`);
        }
        writeFileSync(join(top, '.bundle-source'), `${name} ${hash}\n`);
        rmSync(dest, { recursive: true, force: true });
        renameSync(top, dest);
    } finally {
        rmSync(tmp, { recursive: true, force: true });
    }
    console.log(`${tool.name}: unpacked ${name} into ${relative(root, dest)}`);
}

for (const tool of tools) {
    await fetchTool(tool);
}
