# Development tools

Run on the development machine, not on the Pi; neither is part of the deployment.

## `firefox-control/`: a Firefox that a coding agent can drive

`browser-server.mjs` opens a Playwright Firefox window with a persistent profile
(`firefox-control/firefox-profile/`, gitignored: it holds logins) and accepts commands on
`http://127.0.0.1:9333/cmd`. A person logs in to the consoles in that window; the agent then
navigates, reads the DOM, evaluates code (also inside frames), takes screenshots and reads the
console, without ever seeing passwords.

```sh
cd tools/firefox-control
npm ci && npm run setup     # Playwright and its Firefox build, once
npm start                   # opens the window; leave it running
curl -s -X POST 127.0.0.1:9333/cmd -d '{"action":"goto","url":"https://cloud.mariadb.com/"}'
```

Actions (JSON body): `goto`, `url`, `html`, `eval`, `inject`, `screenshot`, `click` (selector or
x/y), `press`, `frames`, `frameEval` (first frame whose URL contains `match`), `cookies` (names and
attributes, never values), `console` (messages since the last call). Comments in
`browser-server.mjs` show each body.

**Tampermonkey in that window:** Playwright's Firefox enables any signed extension found in the
profile's `extensions/` folder. Download the signed XPI from addons.mozilla.org
(`https://addons.mozilla.org/firefox/downloads/latest/tampermonkey/latest.xpi`), save it as
`firefox-profile/extensions/firefox@tampermonkey.net.xpi` while the window is closed, start the server.
Installing or updating a userscript still needs a person's click in Tampermonkey.

**Limits, do not rely on it for:** Theia webviews (its service workers did not serve
`theia-resource` requests, so webviews stayed blank where a real Firefox shows them) and anything
depending on partitioned third-party cookies (not visible to `cookies`). Verify those in a real
Firefox. `eval` on `about:` pages hangs the server.

## `serve-userscripts.sh`: install URLs for Tampermonkey

```sh
tools/serve-userscripts.sh       # serves private/demos/ at http://127.0.0.1:8765/<vendor>/<script>.user.js
```

Opening a `.user.js` URL makes Tampermonkey offer an install, or an update when `@version` is
higher than the installed one. Works for the agent's Firefox and for the developer's own browser.
