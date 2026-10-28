#!/usr/bin/env node
// Lists the tabs of the everyday Chrome that do not answer DevTools commands.
// chrome-devtools-mcp with --autoConnect attaches to every tab, so a single
// frozen or busy tab makes list_pages and new_page hang until they fail with
// "Network.enable timed out".
//
//   node stuck-tabs.mjs [chrome-user-data-dir]
//
// Reads the endpoint from DevToolsActivePort, attaches to every page, runs a
// trivial Runtime.evaluate with a 3 second limit and prints the host and title
// of each tab that did not answer. Exits with 1 when such tabs exist and with 2
// when Chrome cannot be reached. Needs Node.js 22 or newer.

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const ANSWER_LIMIT_MS = 3000;
const CONNECT_LIMIT_MS = 60000;
const TIMEOUT = Symbol('timeout');

const defaultDir = {
  darwin: join(homedir(), 'Library/Application Support/Google/Chrome'),
  linux: join(homedir(), '.config/google-chrome'),
  win32: join(process.env.LOCALAPPDATA ?? '', 'Google/Chrome/User Data'),
}[process.platform];

function fail(message) {
  console.error(`stuck-tabs: ${message}`);
  process.exit(2);
}

const dir = process.argv[2] ?? defaultDir;
let port;
let path;
try {
  [port, path] = readFileSync(join(dir, 'DevToolsActivePort'), 'utf8').trim().split('\n');
} catch (e) {
  fail(`cannot read DevToolsActivePort in ${dir} (${e.code ?? e.message}). ` +
    'Open Chrome and turn on remote debugging in chrome://inspect/#remote-debugging.');
}

const ws = new WebSocket(`ws://127.0.0.1:${port}${path}`);
const pending = new Map();
let nextId = 0;

function send(method, params = {}, sessionId) {
  return new Promise((resolve, reject) => {
    const id = ++nextId;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params, sessionId }));
  });
}

function within(promise, ms) {
  let timer;
  const limit = new Promise((resolve) => {
    timer = setTimeout(() => resolve(TIMEOUT), ms);
  });
  return Promise.race([promise.finally(() => clearTimeout(timer)), limit]);
}

// Resolves when the tab runs a script. Sessions left attached to a stuck tab
// are dropped by Chrome when the socket closes.
async function answer(page) {
  const { sessionId } = await send('Target.attachToTarget', { targetId: page.targetId, flatten: true });
  await send('Runtime.evaluate', { expression: '1' }, sessionId);
  send('Target.detachFromTarget', { sessionId }).catch(() => {});
}

function hostOf(url) {
  return URL.canParse(url) ? new URL(url).host || url : url;
}

const connectTimer = setTimeout(
  () => fail('Chrome did not accept the connection. Allow the remote debugging prompt in Chrome and run again.'),
  CONNECT_LIMIT_MS,
);

ws.onerror = () => fail(`cannot connect to ws://127.0.0.1:${port}. Is Chrome still running?`);

ws.onmessage = ({ data }) => {
  const message = JSON.parse(data);
  const call = pending.get(message.id);
  if (!call) return;
  pending.delete(message.id);
  if (message.error) call.reject(new Error(message.error.message));
  else call.resolve(message.result);
};

ws.onopen = async () => {
  clearTimeout(connectTimer);
  const { targetInfos } = await send('Target.getTargets');
  const pages = targetInfos.filter((target) => target.type === 'page');
  // A tab that closed during the check counts as answering.
  const results = await Promise.all(
    pages.map((page) => within(answer(page).catch(() => {}), ANSWER_LIMIT_MS)),
  );
  const stuck = pages.filter((_, i) => results[i] === TIMEOUT);
  for (const page of stuck) console.log(`${hostOf(page.url)}\t${page.title}`);
  console.log(`${stuck.length} of ${pages.length} tabs do not answer.`);
  ws.close();
  process.exit(stuck.length ? 1 : 0);
};
