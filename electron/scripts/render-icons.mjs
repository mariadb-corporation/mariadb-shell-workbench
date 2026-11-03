// Renders the app icon from images/mariadb-shell-workbench-icon.svg into electron/resources/ (electron-builder's
// buildResources, generated, not committed):
//   icon.png      1024 px, full bleed: Linux and Windows
//   icon-mac.png  1024 px with the art at 824 px in the middle, Apple's icon grid, so the Dock shows
//                 it as large as other apps' icons
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, '..', '..', 'images', 'mariadb-shell-workbench-icon.svg');
const out = join(here, '..', 'resources');
const svg = readFileSync(source, 'utf8');
const SIZE = 1024;
const MAC_ART = 824;

const render = (markup, size) => new Resvg(markup, { fitTo: { mode: 'width', value: size } }).render().asPng();

// The mac variant: the original SVG nested in a 1024 canvas with a transparent margin.
const viewBox = svg.match(/viewBox="([^"]+)"/)?.[1];
if (!viewBox) throw new Error(`${source} has no viewBox`);
const inner = svg.replace(/^[\s\S]*?(<svg\b)/, '$1')
    .replace(/(<svg\b[^>]*?)\s(?:width|height)="[^"]*"/g, '$1')
    .replace(/(<svg\b[^>]*?)\s(?:width|height)="[^"]*"/g, '$1')
    .replace(/<svg\b/, `<svg x="${(SIZE - MAC_ART) / 2}" y="${(SIZE - MAC_ART) / 2}" width="${MAC_ART}" height="${MAC_ART}"`);
const mac = `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">${inner}</svg>`;

mkdirSync(out, { recursive: true });
writeFileSync(join(out, 'icon.png'), render(svg, SIZE));
writeFileSync(join(out, 'icon-mac.png'), render(mac, SIZE));
console.log(`icons rendered into ${out}`);
