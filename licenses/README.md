# licenses

License files of components whose npm packages ship none, read by `scripts/generate-notices.mjs`
into `THIRD-PARTY-NOTICES.txt`. `lumino-LICENSE` is `github.com/jupyterlab/lumino`'s `LICENSE`
(the same at the tags of all shipped `@lumino/*` versions; check again when their versions change).
Eclipse Theia's are from its repository at the tag of the Theia
version in `package.json` (`https://github.com/eclipse-theia/theia/tree/v<version>`); fetch them
again on a Theia upgrade.

`npm/<name>@<version>` (`+` for `/` in scoped names): npm packages that ship no license file, with
the license from their repository at the release tag, or from the default branch when the tag has
none (`@tootallnate/once`, `buffer-alloc`, `buffer-alloc-unsafe`, `buffer-fill`, `eastasianwidth`,
`isarray`, `resolve-package-path`). Where the package's own README carries the full license, that
section is used (`agent-base`, the `*-proxy-agent` packages, `cookie-signature`). `font-awesome` is
its 4.7.0 README's license section plus the SIL OFL 1.1 text (SPDX license list); `type-fest` is MIT
and CC0, both texts. `use-composed-ref` has no license text anywhere and stays listed as MIT. A
version change of one of these packages leaves it without a text until its file is added for the
new version.

The same files serve packages bundled inside a third-party VS Code extension in `plugins/`:
`typescript@5.6.3` (in `vscode.typescript-language-features`, `deps/typescript`, which VS Code's
build strips of its license files) is `LICENSE.txt` and `ThirdPartyNoticeText.txt` of that version's
npm package. A new `vscode.typescript-language-features` may bundle another TypeScript version.
