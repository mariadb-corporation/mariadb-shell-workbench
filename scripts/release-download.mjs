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
    mkdirSync(dir, { recursive: true });
    // Written next to the target and renamed, so an interrupted download never looks cached.
    const partial = `${file}.partial`;
    // GitHub's download hosts drop a connection now and then (seen on CI runners); a 404 is final.
    for (let attempt = 1; ; attempt++) {
        console.log(`downloading ${url}${attempt > 1 ? ` (attempt ${attempt})` : ''}`);
        try {
            const response = await fetch(url, { headers });
            if (response.status === 404) {
                throw Object.assign(new Error(`${url}: 404 Not Found`), { final: true });
            }
            if (!response.ok) {
                throw new Error(`${url}: ${response.status} ${response.statusText}`);
            }
            writeFileSync(partial, Buffer.from(await response.arrayBuffer()));
            break;
        } catch (error) {
            if (error.final || attempt === 4) {
                throw error;
            }
            console.warn(`  ${error.message}${error.cause ? ` (${error.cause.message})` : ''}; retrying`);
            await new Promise(resolve => setTimeout(resolve, attempt * 5000));
        }
    }
    if (expectedSha256 && sha256(partial) !== expectedSha256) {
        throw new Error(`${name}: SHA-256 does not match the release's checksum`);
    }
    renameSync(partial, file);
    return file;
}
