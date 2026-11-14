---
description: Cut a release of the desktop app, suggesting its next YY.MM.x version and moving the bundled MariaDB Shell extension, MariaDB Shell Agent, MariaDB Shell and mariadb-restd to newer releases where there are any, show the version grid for approval, PR it, push it to release/candidate, wait for the six-platform build, and publish it as a GitHub pre-release. Usage: /release [version|-] [extension|-] [agent|-] [shell|-] [restd|-]
---

# Release Command

Arguments as typed: `$ARGUMENTS`

Split that string on whitespace. The positions are:

1. **The version**: the app's version, `version` in `package.json` and
   `electron/package.json` (the two must be equal). It names the packages
   (`mariadb-shell-workbench-<version>-<os>-<arch>.<ext>`) and the tag
   `v<version>`.
2. **The extension pin**: `MARIADB_EXTENSION_TAG`'s default in
   `scripts/fetch-extensions.mjs`, the mariadb-corporation/vscode-extension
   release whose `mariadb-shell-<v>.vsix` the app bundles.
3. **The agent pin**: `MARIADB_SHELL_AGENT_TAG`'s default in
   `scripts/fetch-extensions.mjs`, the mariadb-corporation/mariadb-shell-agent
   release whose `mariadb-shell-agent-<v>-universal.vsix` the app bundles.
4. **The shell pin**: `MARIADB_SHELL_TAG`'s default in
   `scripts/fetch-bundled-tools.mjs`, the mariadb-corporation/mariadb-shell
   release unpacked into `bundle/mariadb-shell`.
5. **The daemon pin**: `MARIADB_RESTD_TAG`'s default in
   `scripts/fetch-bundled-tools.mjs`, the mariadb-corporation/rest-daemon
   release unpacked into `bundle/mariadb-restd`.

All five are optional, so a bare `/release` works. A `-` in a position means
"not given", so a later position can be given without an earlier one
(`/release - - - 26.11.3`). What is not given is suggested in step 2: the
next `YY.MM.x` for the version, and the latest published release for each
pin, when it is newer than the current one. If a sixth word is left over,
stop and ask what it means.

Every version is a bare `MAJOR.MINOR.PATCH` such as `26.11.0`. Strip a
leading `v` if one was given and say so. The app's version is bare in
`package.json`; the pins and the git tag carry the `v` (`'v26.11.1'`).

**Every release is a GitHub pre-release.** The app is not signed yet, so no
release is marked stable or "Latest", whatever the user's wording suggests.
If the user asks for a stable release, stop and say that it needs signed
packages first.

**The pins are exact.** Unlike a floor, a pin is the very release that goes
into the package, on all six platforms. CI builds with these defaults; the
environment variables only override them for a one-off build.

Read `.claude/PROJECT_CONTEXT.md` and the README's "Desktop app" and
"Release builds" sections before starting. The two workflows are
`.github/workflows/release.yml` (Workbench-Release: builds the six platforms
on every push to `release/candidate`) and `.github/workflows/publish-release.yml`
(Publish Release: turns a successful run into a GitHub release).

The remote is `origin` = `mariadb-corporation/mariadb-shell-workbench`. Check
`git remote -v`. If it is missing, stop and report it.

## 1. Preconditions

- `git status --short` must be clean and the current branch must be `main`,
  level with `origin/main` after `git fetch --tags origin`. If not, stop and
  report. Do not stash or reset anything.
- `gh auth status` must succeed. If it fails, stop: every later step needs it.
- Both workflows must be on `main` (`git ls-tree origin/main .github/workflows/`
  lists `release.yml` and `publish-release.yml`). Publish Release can only be
  started once it is on the default branch.
- `version` in `package.json` and `electron/package.json` must be equal. If
  not, stop and report both.
- `v<version>` must not exist as a tag, locally or on `origin`
  (`git ls-remote --tags origin v<version>`), nor as a release
  (`gh release view v<version>`). When the version is suggested, check this in
  step 2, once it is known.

## 2. Check the versions and show the grid

Do all of this before changing anything.

**The app's version.** Take the highest of this repository's tags
(`git tag -l 'v*' | sort -V`) and its releases
(`gh release list --exclude-drafts --limit 30 --json tagName`). Report it,
or that there is neither (the first release).

- **None given:** suggest `YY.MM.x` from today's date (`date +%y.%-m`): `YY`
  is the year's last two digits, `MM` the month without a leading zero
  (`26.9.0`, never `26.09.0`), and `x` counts the releases of that month: `0`
  for the month's first, one more than the highest `x` among the tags that
  start with `vYY.MM.` otherwise. For the first release, when `version` in
  `package.json` already is a `YY.MM.x` of this month, suggest it as it is.
  If the suggestion does not sort above the highest tag, stop and report it.
- **One given:** it must sort above the highest tag, or stop. For the first
  release it may equal `version` in `package.json`. If it does not follow
  `YY.MM.x` for this month, say so and ask whether to use it anyway.

**The four pins.** Read each current pin from its script. For each repository
list the published releases:

```bash
gh release list --repo mariadb-corporation/<repo> --exclude-drafts --limit 30 --json tagName,isPrerelease,publishedAt
```

for `<repo>` = `vscode-extension`, `mariadb-shell-agent`, `mariadb-shell` and
`rest-daemon`. Most of their releases are prereleases, so `releases/latest`
404s: do not use it. Sort the `tagName`s as versions (strip the `v`, then
`sort -V`), not by date.

- **The current pin is not in the list** → stop, whatever was given. Every
  build would fail on a 404.
- **None given:** if the pin is the highest release, keep it. If a newer one
  exists, suggest moving to it.
- **One given:** not in the list → stop. Below the current pin → stop and
  ask: going back is not a normal release step. Equal → nothing to move. A
  higher one exists → say so and ask.

**The assets.** Whichever release each pin ends up at, check that it carries
what the build downloads, or a platform's build fails after 20 minutes:

```bash
gh release view <tag> --repo mariadb-corporation/<repo> --json assets --jq '.assets[].name'
```

- vscode-extension: `mariadb-shell-<v>.vsix`.
- mariadb-shell-agent: `mariadb-shell-agent-<v>-universal.vsix`.
- mariadb-shell: `SHA256SUMS`, and one archive per platform that the
  `pattern` in `scripts/fetch-bundled-tools.mjs` matches: `macos*-arm-64bit`,
  `macos*-x86-64bit`, `linux-glibc*-x86-64bit`, `linux-glibc*-arm-64bit`,
  `windows-x86-64bit`, `windows-arm-64bit` (all `.tar.gz`). The Linux glibc
  must not be newer than 2.35, the glibc of the `ubuntu-22.04` runners and
  the oldest the app supports.
- rest-daemon: `SHA256SUMS`, and `macos-arm64`, `macos-x86_64`,
  `linux-x86_64`, `linux-aarch64` (`.tar.gz`) and `windows-x64` (`.zip`).
  There is no Windows arm64 build so far; the app is built without the
  daemon there, with a warning. If a release now has one, say so: the
  `arch` map in `fetch-bundled-tools.mjs` needs a `win32` `arm64` entry
  before it is used.

A missing asset → stop and report it.

**The cross-checks.** The bundled tools must satisfy the bundled extension.
Read its floors at the extension pin:

```bash
gh api "repos/mariadb-corporation/vscode-extension/contents/src/shell/constants.ts?ref=<ext-tag>" -H "Accept: application/vnd.github.raw" | grep 'MINIMUM_SHELL_VERSION ='
gh api "repos/mariadb-corporation/vscode-extension/contents/src/mcp/restdApi.ts?ref=<ext-tag>" -H "Accept: application/vnd.github.raw" | grep 'MINIMUM_RESTD_VERSION ='
```

- The shell pin must be at or above `MINIMUM_SHELL_VERSION`. If not, the
  extension rejects the bundled shell and downloads its own on first start:
  stop, and suggest the floor (or newer) as the shell pin.
- The daemon pin should equal `MINIMUM_RESTD_VERSION`, the release the
  extension installs. Below it → stop, as for the shell. Above it → say so;
  it is not an error.

If a file has moved in the extension repository, say so and ask rather than
skipping the check.

**The grid.** Show one table, every row filled, then stop:

| Component | Repository | Current | Latest published | This release | Given / suggested / unchanged |
|---|---|---|---|---|---|
| MariaDB Shell Workbench | mariadb-shell-workbench | … | — | … | … |
| MariaDB Shell extension | vscode-extension | … | … | … | … |
| MariaDB Shell Agent | mariadb-shell-agent | … | … | … | … |
| MariaDB Shell | mariadb-shell | … | … | … | … |
| MariaDB REST Daemon | rest-daemon | … | … | … | … |

Below it, list in a few lines: the result of the asset checks per pin (the
publish date of each release that moves), the cross-checks (extension floors
against the shell and daemon pins), and the versions this command does not
move but the package carries, for the record: Theia and Electron from
`electron/package.json`. Say that the release will be a GitHub pre-release.

**Ask the user to approve the grid, always**, even when every version was
given: this is the release's only review before 25 minutes of CI. They may
accept it or change any version. Run the checks again for what changed and
show the grid again. Go on only on an explicit yes.

## 3. Branch and set the versions

```bash
git switch -c wip/release-<version>
```

Make each change that applies, in this order, and commit each on its own so
the PR can be reviewed a step at a time. Skip a step whose version does not
move. After each, `git status --short` must list exactly the files named.

1. **The pins** (`scripts/fetch-extensions.mjs`,
   `scripts/fetch-bundled-tools.mjs`): change the default tag of each pin
   that moves, and nothing else. In `fetch-bundled-tools.mjs`, also update the
   example archive names in the comment above `tools` when the shell or daemon
   pin moves. Commit as "Bundle …", naming each component and its new
   version.
2. **The version**: in the root and in `electron/`:
   ```bash
   npm version <version> --no-git-tag-version --ignore-scripts
   (cd electron && npm version <version> --no-git-tag-version --ignore-scripts)
   ```
   Changes `package.json`, `package-lock.json`, `electron/package.json` and
   `electron/package-lock.json`, and only their `version` fields: check with
   `git diff`. Commit as "Set the version to <version>".

## 4. Verify locally

On this machine, check that what CI will download unpacks:

```bash
node scripts/fetch-bundled-tools.mjs
electron/bundle/mariadb-shell/bin/mariadb-shell --version     # must name the shell pin
electron/bundle/mariadb-restd/bin/mariadb-restd --version     # must name the daemon pin
```

For the two extensions, download the `.vsix` files only, with
`releaseAsset()` from `scripts/release-download.mjs`
(`node -e "import('./scripts/release-download.mjs').then(m => m.releaseAsset('<owner/repo>', '<tag>', '<asset>')).then(console.log)"`).
Do not run `scripts/fetch-extensions.mjs`: it replaces the user's
development extensions in `plugins/`.

`electron/bundle/` and `.cache/` are gitignored, so `git status --short` must
still be clean. A full local `scripts/build-standalone.sh` is not needed:
step 6 builds every platform.

## 5. Open the PR

```bash
git push -u origin wip/release-<version>
gh pr create --repo mariadb-corporation/mariadb-shell-workbench --base main --head wip/release-<version> \
  --title "Release <version>: …" --body-file <scratch>/pr.md
```

The title names what moves (for example "Release 26.11.1: MariaDB Shell
26.11.2 and the 26.11.1 extensions"). The body carries the grid of step 2,
the asset and cross-check results, the local check of step 4, and a test
plan: the push to `release/candidate`, the six-platform build and the
pre-release. It ends with the PR attribution line.

Then **stop and ask the user to review and merge the PR**, giving its URL.
Do not merge it yourself. When the user says it is merged, confirm with
`gh pr view <N> --json state,mergeCommit,headRefOid` that `state` is
`MERGED`, and note the merge commit.

## 6. Push to release/candidate and wait for the build

```bash
git switch main && git pull --ff-only origin main
git rev-parse HEAD          # must be the PR's merge commit
```

If `HEAD` is not the merge commit (`main` moved on since), stop and ask: the
release should be exactly what was reviewed.

`release/candidate` must only ever move forward to a commit of `main`. If it
exists on `origin`, it must be an ancestor of `HEAD`
(`git merge-base --is-ancestor origin/release/candidate HEAD`). If it is not,
stop and report it. Never force-push it.

```bash
git push origin HEAD:refs/heads/release/candidate
```

Find the run the push started (it can take a minute to appear):

```bash
gh run list --workflow release.yml --branch release/candidate --commit <merge-sha> --json databaseId,status,url
```

Give the user its URL, then wait for it in the background (about 25
minutes), not by polling:

```bash
gh run watch <run-id> --exit-status --interval 60 > /dev/null
```

When it ends, report each platform's result
(`gh run view <run-id> --json jobs --jq '.jobs[] | "\(.name): \(.conclusion)"'`).
If a job failed, show the end of its log (`gh run view <run-id> --log-failed | tail -80`)
and stop. A download that GitHub dropped (`fetch failed`, `other side closed`)
after all four attempts may be rerun once with `gh run rerun <run-id> --failed`,
after asking. Anything else needs a fix through a new PR; then the release
starts again at step 3 with the same version.

## 7. Publish the pre-release

**The tag first.** The repository's "Create Release" ruleset lets only admins
create, move or delete `v*` tags, so Publish Release cannot create one: its
token is refused (`Cannot create ref due to creations being restricted`). The
tag is created here, from the user's account, on the commit the build ran on
(the merge commit), as an annotated tag:

```bash
git tag -a v<version> <merge-sha> -m "MariaDB Shell Workbench <version>" \
  -m "<one paragraph: what is new, and the bundled versions: MariaDB Shell, MariaDB REST Daemon, the MariaDB Shell extension and MariaDB Shell Agent>. Built by run <run-id>."
git push origin refs/tags/v<version>
git ls-remote --tags origin 'v<version>*'      # the tag object, and ^{} the merge commit
```

Push only this tag: never `git push --tags`, which would publish the local
`archive/*` tags. If the push is refused, the `gh` user is not an admin of
the repository: stop and report it. A tag pushed by mistake can only be
deleted by an admin, too.

Then a dry run, which checks that the tag is on the build's commit, that all
six platforms are in the run, and prints the release notes:

```bash
gh workflow run publish-release.yml -f run_id=<run-id> -f tag=v<version> -f prerelease=true -f dry_run=true
```

Find its run (`gh run list --workflow publish-release.yml --limit 1 --json databaseId,url`),
wait for it with `gh run watch <id> --exit-status`, and read its log
(`gh run view <id> --log | grep -A60 'DRY RUN'`). It must say
`Would create release v<version> on <merge-sha> (tag in place)` and
`prerelease=true`, and the notes must carry the macOS install command with
`MARIADB_SHELL_WORKBENCH_TAG=v<version>`. If it
says it would update an existing release, stop: step 1 found no such release,
so someone else published one in the meantime.

Then publish:

```bash
gh workflow run publish-release.yml -f run_id=<run-id> -f tag=v<version> -f prerelease=true -f dry_run=false
```

and wait for it in the same way. Then make sure the release is a
pre-release, whatever the workflow's input said, and check it:

```bash
gh release edit v<version> --prerelease=true
gh release view v<version> --json isPrerelease,isDraft,tagName,targetCommitish,assets \
  --jq '{isPrerelease, isDraft, tagName, targetCommitish, assets: [.assets[].name]}'
```

- `isPrerelease` must be `true` and `isDraft` `false`.
- The tag must point at the merge commit:
  `git fetch --tags origin && git rev-parse v<version>^{commit}`.
- The assets must be eleven: `SHA256SUMS` and, with
  `mariadb-shell-workbench-<version>-` in front, `mac-arm64.dmg`,
  `mac-arm64.zip`, `mac-x64.dmg`, `mac-x64.zip`, `linux-x86_64.AppImage`,
  `linux-x64.tar.gz`, `linux-arm64.AppImage`, `linux-arm64.tar.gz`,
  `win-x64.exe` and `win-arm64.exe`.
- `gh release list --limit 5` must not show `v<version>` as `Latest`.
- The macOS installer must find and verify the new release; this downloads
  the package (about 400 MB) into the scratchpad, not into `/Applications`:
  `MARIADB_SHELL_WORKBENCH_TAG=v<version> MARIADB_SHELL_WORKBENCH_APPDIR=<scratch>/apps ./install.sh`
  must end with `Installed`. Remove `<scratch>/apps` afterwards.

Anything else → report it and stop.

## 8. Clean up and report

Delete the local `wip/release-<version>` branch, and on `origin` once its
remote head matches the PR's `headRefOid`. Then tell the user the release is
published, with:

- the merged PR and its merge commit;
- the build run and the time it took;
- the release URL, its tag, and that it is a pre-release;
- the final grid: the app's version and each bundled component, with what
  moved;
- what was not tested: the packages are unsigned and have not been installed
  on any platform by this command; suggest which ones to try first;
- anything that did not go as expected.

If the release taught something that stays true, such as a step that has to
change, record it with `/checkpoint` and open a small PR for it. Do not
record the release itself as git state.
