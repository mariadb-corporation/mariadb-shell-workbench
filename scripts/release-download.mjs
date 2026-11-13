// Downloads a file attached to a GitHub release of a public repository into the build cache
// (.cache/releases/<owner>/<repo>/<tag>/, gitignored), and reuses the cached copy on the next build.
// Direct download URLs need no token and count against no API rate limit; GITHUB_TOKEN is sent
// when set (GitHub Actions), which also covers a repository that turns private.
import { createHash } from 'crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

export const root = join(dirname(fileURLToPath(import.meta.url)), '..');

export const sha256 = file => createHash('sha256').update(readFileSync(file)).digest('hex');

/**
 * Returns the local path of `name` from release `tag` of `repo` (owner/name), downloading it
 * when it is not cached yet. With `expectedSha256`, a cached copy that does not match is
 * downloaded again, and a download that does not match fails.
 */
export async function releaseAsset(repo, tag, name, expectedSha256) {
    const dir = join(root, '.cache', 'releases', repo, tag);
    const file = join(dir, name);
    if (existsSync(file) && (!expectedSha256 || sha256(file) === expectedSha256)) {
        return file;
    }
    const url = `https://github.com/${repo}/releases/download/${tag}/${name}`;
    const headers = process.env.GITHUB_TOKEN ? { Authorization: `Bearer ${process.env.GITHUB_TOKEN}` } : {};
    console.log(`downloading ${url}`);
    const response = await fetch(url, { headers });
    if (!response.ok) {
        throw new Error(`${url}: ${response.status} ${response.statusText}`);
    }
    mkdirSync(dir, { recursive: true });
    // Written next to the target and renamed, so an interrupted download never looks cached.
    const partial = `${file}.partial`;
    writeFileSync(partial, Buffer.from(await response.arrayBuffer()));
    if (expectedSha256 && sha256(partial) !== expectedSha256) {
        throw new Error(`${name}: SHA-256 does not match the release's checksum`);
    }
    renameSync(partial, file);
    return file;
}
