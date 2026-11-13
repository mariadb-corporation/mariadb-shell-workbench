#!/usr/bin/env node
// Writes THIRD-PARTY-NOTICES.txt: the third-party components MariaDB Shell Workbench ships, for the browser
// app (package-lock.json) and the desktop app (electron/package-lock.json). npm packages come from the
// production entries of both lock files with the license texts found in node_modules; the bundled VS
// Code extensions and Electron are listed with where their own license files are.
//
//   node scripts/generate-notices.mjs        (npm run notices; run by scripts/build-standalone.sh)
//
// Needs node_modules installed in the root, in electron/, or both: a package missing from one tree is
// looked up in the other by name and version.
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const trees = [root, join(root, 'electron')].filter(dir => existsSync(join(dir, 'package-lock.json')));
const LICENSE_FILE = /^(licen[cs]e|copying|notices?)([-._].*)?$/i;
const RULE = '='.repeat(78);
// Packages that ship no license file get their project's license from licenses/: a whole family by
// name, or one package version in licenses/npm/<name with + for />@<version>.
const LICENSE_FROM_REPO = [[/^@lumino\//, 'lumino-LICENSE']];
const licenseFromRepo = pkg => {
    const family = LICENSE_FROM_REPO.find(([pattern]) => pattern.test(pkg.name))?.[1];
    const file = family ? join(root, 'licenses', family)
        : join(root, 'licenses', 'npm', `${pkg.name.replace(/\//g, '+')}@${pkg.version}`);
    return existsSync(file) ? readFileSync(file, 'utf8').trim() : undefined;
};

const readJson = file => JSON.parse(readFileSync(file, 'utf8'));
const licenseOf = pkg => typeof pkg.license === 'string' ? pkg.license
    : pkg.license?.type ?? (Array.isArray(pkg.licenses) ? pkg.licenses.map(l => l.type ?? l).join(' OR ') : 'UNKNOWN');

// name@version → { name, version, license, repository, dirs[] }
const packages = new Map();
for (const tree of trees) {
    for (const [key, entry] of Object.entries(readJson(join(tree, 'package-lock.json')).packages)) {
        if (!key || entry.dev || entry.link || !key.includes('node_modules/')) continue;
        const name = entry.name ?? key.slice(key.lastIndexOf('node_modules/') + 'node_modules/'.length);
        const id = `${name}@${entry.version}`;
        const dir = join(tree, key);
        const known = packages.get(id) ?? { name, version: entry.version, license: entry.license, dirs: [] };
        if (existsSync(join(dir, 'package.json'))) known.dirs.push(dir);
        packages.set(id, known);
    }
}

// Packages a third-party extension bundles (deps/<name>, node_modules/<name>): listed and given their
// license text like the npm packages above, with the extension that carries them. MariaDB's own
// extensions are left out: what they bundle is covered by their own license files.
const plugins = join(root, 'plugins');
const pluginIds = existsSync(plugins) ? readdirSync(plugins).filter(id => existsSync(join(plugins, id, 'extension', 'package.json'))).sort() : [];
const subdirs = dir => existsSync(dir) ? readdirSync(dir).filter(f => statSync(join(dir, f)).isDirectory()) : [];
for (const id of pluginIds.filter(id => !id.startsWith('mariadb.'))) {
    for (const holder of ['deps', 'node_modules']) {
        const base = join(plugins, id, 'extension', holder);
        const dirs = subdirs(base).flatMap(d => d.startsWith('@') ? subdirs(join(base, d)).map(s => join(base, d, s)) : [join(base, d)]);
        for (const dir of dirs.filter(d => existsSync(join(d, 'package.json')))) {
            const manifest = readJson(join(dir, 'package.json'));
            const key = `${manifest.name}@${manifest.version}`;
            const known = packages.get(key) ?? { name: manifest.name, version: manifest.version, dirs: [] };
            known.dirs.push(dir);
            known.inExtension = id;
            packages.set(key, known);
        }
    }
}

const licenseTexts = dir => readdirSync(dir)
    .filter(file => LICENSE_FILE.test(file) && statSync(join(dir, file)).isFile())
    .sort()
    .map(file => readFileSync(join(dir, file), 'utf8').replace(/\r\n/g, '\n').trim())
    .filter(Boolean);

// One section per distinct license text, naming every package that carries it.
const byText = new Map();
const withoutText = [];
const list = [...packages.values()].sort((a, b) => a.name.localeCompare(b.name) || a.version.localeCompare(b.version, undefined, { numeric: true }));
for (const pkg of list) {
    const dir = pkg.dirs[0];
    if (dir) {
        const manifest = readJson(join(dir, 'package.json'));
        pkg.license = licenseOf(manifest);
        const repo = typeof manifest.repository === 'string' ? manifest.repository : manifest.repository?.url;
        pkg.repository = repo?.replace(/^git\+/, '').replace(/\.git$/, '');
    }
    pkg.license ??= 'UNKNOWN';
    const own = dir ? licenseTexts(dir) : [];
    const fromRepo = own.length ? undefined : licenseFromRepo(pkg);
    const texts = fromRepo ? [fromRepo] : own;
    if (texts.length === 0) {
        withoutText.push(pkg);
        continue;
    }
    const text = texts.join(`\n\n${'-'.repeat(78)}\n\n`);
    (byText.get(text) ?? byText.set(text, []).get(text)).push(pkg);
}

const label = pkg => `${pkg.name} ${pkg.version}${pkg.inExtension ? ` (in ${pkg.inExtension})` : ''}`;
const pluginLine = id => {
    const manifest = readJson(join(plugins, id, 'extension', 'package.json'));
    const files = readdirSync(join(plugins, id, 'extension')).filter(f => LICENSE_FILE.test(f)).sort();
    return `   - ${manifest.displayName ?? id} (${id} ${manifest.version}): ${files.map(f => `plugins/${id}/extension/${f}`).join(', ') || 'no license file'}`;
};
const builtIn = pluginIds.filter(id => id.startsWith('vscode.'));
const vscodeLicense = builtIn.length ? readFileSync(join(plugins, builtIn[0], 'extension', 'LICENSE-vscode.txt'), 'utf8').trim() : '';

const out = [];
out.push(`Third-Party Notices

MariaDB Shell Workbench
${RULE}

MariaDB Shell Workbench is released under version 2 of the GNU General Public
License (GPLv2); see LICENSE. It is built on Eclipse Theia and ships the
third-party components below, each under its own license. In the desktop app
these files are in the app's resources folder (Contents/Resources on macOS).

Eclipse Theia

   Eclipse Theia is licensed under EPL-2.0 OR GPL-2.0-only WITH
   Classpath-exception-2.0; the @theia/* packages below are Theia. Its
   notices and both license texts are at the end of this file.
   MariaDB Shell Workbench modifies @theia/core and @theia/plugin-ext; the
   modifications are the files in patches/ of the MariaDB Shell Workbench
   source code and are provided under the same terms as Theia.

Electron and Chromium (desktop app)

   Electron is licensed under the MIT License (LICENSE.electron.txt). The
   licenses of Chromium and the other components Electron includes are in
   LICENSES.chromium.html.

MariaDB Shell and MariaDB REST Daemon (desktop app)

   The desktop app bundles a release of MariaDB Shell and of the MariaDB REST
   Daemon for its platform, in resources/app/bundle/mariadb-shell/ and
   resources/app/bundle/mariadb-restd/. Each carries its own licensing
   information, including the third-party components it contains:
   bundle/mariadb-shell/share/mariadb-shell/LICENSE and
   bundle/mariadb-restd/docs/LICENSE.

Bundled VS Code extensions

   Each extension is in plugins/ (resources/app/plugins/ in the desktop app)
   with its own license files:

${pluginIds.map(pluginLine).join('\n')}
`);
if (vscodeLicense) {
    out.push(`   The built-in VS Code extensions (vscode.*, from Open VSX) carry this license:

${vscodeLicense.split('\n').map(l => l ? `   ${l}` : '').join('\n')}
`);
}
out.push(`npm packages

   The JavaScript packages in the browser app and the desktop app, and those a
   bundled extension carries (marked with the extension), with the license each
   declares. Their license texts follow, one section per distinct text.

${list.map(pkg => `   - ${label(pkg)}: ${pkg.license}`).join('\n')}
`);
for (const [text, pkgs] of byText) {
    out.push(`${RULE}
${pkgs.map(label).join(', ')}
${[...new Set(pkgs.map(p => p.repository).filter(Boolean))].join('\n')}
${RULE}

${text}
`);
}
if (withoutText.length) {
    out.push(`${RULE}
Packages without a license file of their own (license as declared in package.json)
${RULE}

${withoutText.map(pkg => `   - ${label(pkg)}: ${pkg.license}${pkg.dirs.length ? '' : ' (not installed on this platform)'}`).join('\n')}
`);
}

// The @theia/* packages ship no license files; Theia's own, from its repository (licenses/).
for (const [title, file] of [
    ['Eclipse Theia: notices', 'eclipse-theia-NOTICE.md'],
    ['Eclipse Theia: Eclipse Public License 2.0', 'eclipse-theia-LICENSE-EPL'],
    ['Eclipse Theia: GNU General Public License 2.0 with the Classpath exception', 'eclipse-theia-LICENSE-GPL-2.0-ONLY-CLASSPATH-EXCEPTION'],
]) {
    out.push(`${RULE}
${title}
${RULE}

${readFileSync(join(root, 'licenses', file), 'utf8').trim()}
`);
}

writeFileSync(join(root, 'THIRD-PARTY-NOTICES.txt'), out.join('\n').replace(/[ \t]+$/gm, ''));
console.log(`THIRD-PARTY-NOTICES.txt: ${list.length} npm packages, ${byText.size} license texts, ${pluginIds.length} extensions`);
