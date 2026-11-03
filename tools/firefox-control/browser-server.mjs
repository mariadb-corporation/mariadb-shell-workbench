// Keeps a Firefox window (persistent profile in ./firefox-profile, next to this file) open and
// accepts control commands on http://127.0.0.1:9333 (localhost only). See ../README.md.
//
//   POST /cmd  {"action":"goto","url":"..."}
//              {"action":"url"}
//              {"action":"html","selector":"optional css"}
//              {"action":"eval","code":"js expression or function body"}
//              {"action":"inject","file":"path/to/script.user.js"}
//              {"action":"screenshot","path":"shot.png","fullPage":false}
//              {"action":"click","selector":"css"}  or  {"action":"click","x":10,"y":20}
//              {"action":"press","key":"Control+Shift+P"}
//              {"action":"frames"}  /  {"action":"frameEval","match":"webview.","code":"..."}
//              {"action":"cookies","domain":"example.com"}   (attributes only, never values)
//              {"action":"console"}                         (messages since the last call)
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { firefox } from 'playwright';

const PORT = 9333;
// Holds logins and Tampermonkey: gitignored, never commit it.
const profileDir = path.join(path.dirname(fileURLToPath(import.meta.url)), 'firefox-profile');

const context = await firefox.launchPersistentContext(profileDir, {
  headless: false,
  viewport: null,
});
const consoleLog = [];
const watch = (p) => {
  p.on('console', (m) => consoleLog.push(`[${m.type()}] ${m.text()}`));
  p.on('pageerror', (e) => consoleLog.push(`[pageerror] ${e.message}`));
};
context.pages().forEach(watch);
context.on('page', watch);

const page = () => context.pages().at(-1) ?? context.newPage();

async function handle(cmd) {
  const p = await page();
  switch (cmd.action) {
    case 'goto':
      await p.goto(cmd.url, { waitUntil: 'domcontentloaded' });
      return { url: p.url(), title: await p.title() };
    case 'url':
      return { url: p.url(), title: await p.title() };
    case 'html':
      return cmd.selector
        ? await p.$$eval(cmd.selector, (els) => els.map((e) => e.outerHTML))
        : await p.content();
    case 'eval':
      return await p.evaluate(cmd.code);
    case 'inject': {
      // Strip the userscript header and run the body in the page.
      const src = fs.readFileSync(cmd.file, 'utf8')
        .replace(/\/\/ ==UserScript==[\s\S]*?\/\/ ==\/UserScript==/, '');
      await p.addScriptTag({ content: src });
      return 'injected';
    }
    case 'screenshot':
      await p.screenshot({ path: cmd.path ?? 'shot.png', fullPage: !!cmd.fullPage });
      return { path: path.resolve(cmd.path ?? 'shot.png') };
    case 'cookies':
      // Names and attributes only, never values: {domain} filters by substring.
      return (await context.cookies())
        .filter((ck) => !cmd.domain || ck.domain.includes(cmd.domain))
        .map(({ value, ...rest }) => ({ ...rest, valueLength: value.length }));
    case 'frames':
      return p.frames().map((f) => f.url());
    case 'frameEval': {
      // Evaluate in the first frame whose URL contains {match}.
      const f = p.frames().find((fr) => fr.url().includes(cmd.match));
      if (!f) throw new Error(`no frame matching ${cmd.match}`);
      return await f.evaluate(cmd.code);
    }
    case 'click':
      // Real mouse click: {selector} or {x, y} in CSS pixels.
      if (cmd.selector) await p.click(cmd.selector, { timeout: 10000 });
      else await p.mouse.click(cmd.x, cmd.y);
      return 'clicked';
    case 'press':
      await p.keyboard.press(cmd.key);
      return 'pressed';
    case 'console': {
      const out = consoleLog.splice(0);
      return out;
    }
    default:
      throw new Error(`unknown action ${cmd.action}`);
  }
}

http.createServer(async (req, res) => {
  let body = '';
  for await (const chunk of req) body += chunk;
  try {
    const result = await handle(JSON.parse(body || '{}'));
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, result }, null, 2));
  } catch (e) {
    res.writeHead(500, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: false, error: String(e) }));
  }
}).listen(PORT, '127.0.0.1', () => console.log(`browser server on ${PORT}`));

context.on('close', () => process.exit(0));
