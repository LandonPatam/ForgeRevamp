// Starts an isolated three-player AI match, checks the real WebSocket protocol, then stops only that process.
import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:net';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const bridgeRoot = fileURLToPath(new URL('../', import.meta.url));
const portProbe = createServer();
await new Promise(resolve => portProbe.listen(0, '127.0.0.1', resolve));
const port = process.env.FORGE_SMOKE_PORT || String(portProbe.address().port);
await new Promise(resolve => portProbe.close(resolve));
const url = `ws://127.0.0.1:${port}/ws`;
// Oracle's PATH shim launches another java.exe; resolve the actual JVM so cleanup owns the game process.
const javaSettings = spawnSync('java', ['-XshowSettings:properties', '-version'], {encoding: 'utf8', windowsHide: true});
const javaHome = javaSettings.stderr?.match(/^\s*java.home = (.+)$/m)?.[1].trim();
if (!javaHome) throw new Error('Could not locate the JVM home');
const child = spawn(join(javaHome, 'bin', process.platform === 'win32' ? 'java.exe' : 'java'), ['-Xmx4g', '-cp', 'target/classes;target/lib/*', 'forgeui.bridge.BridgeMain', '--assets', '../forge/forge-gui', '--port', port, '--opponents', '2'], {cwd: bridgeRoot, windowsHide: true});
let tail = '', startupFailure, ready = false;
for (const stream of [child.stdout, child.stderr]) stream.on('data', data => { const text = data.toString(); ready ||= text.includes('Bridge ready:'); tail = (tail + text).slice(-4000); });
child.on('error', error => { startupFailure = error; });
let counter = 0, passed = 0;
const peers = [];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const check = (value, message) => { assert.ok(value, message); passed++; };

async function connect() {
  const ws = new WebSocket(url);
  const messages = [];
  ws.onmessage = event => messages.push(JSON.parse(event.data));
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  const peer = {
    ws, messages,
    async wait(predicate, start = 0) {
      const deadline = Date.now() + 15000;
      while (Date.now() < deadline) {
        const message = messages.slice(start).find(predicate);
        if (message) return message;
        await pause(20);
      }
      throw new Error('Timed out waiting for bridge response');
    },
    send(request, state) {
      const requestId = String(++counter);
      ws.send(JSON.stringify({protocolVersion: 2, sessionId: state.sessionId, revision: state.revision, requestId, ...request}));
      return this.wait(m => m.requestId === requestId && ['ack', 'error'].includes(m.type));
    },
  };
  peers.push(peer);
  return peer;
}

try {
  let peer;
  const deadline = Date.now() + 90000;
  while (Date.now() < deadline && !peer) {
    if (startupFailure || child.exitCode !== null) throw startupFailure || new Error('Java exited during startup');
    if (!ready) { await pause(400); continue; }
    try { peer = await connect(); } catch { await pause(400); }
  }
  if (!peer) throw new Error('Bridge startup timed out');
  let state = await peer.wait(m => m.type === 'state' && !m.loading);
  check(state.protocolVersion === 2 && state.players.length === 3, 'Expected protocol v2 and three players');
  const forbiddenOrigin = await fetch(`http://127.0.0.1:${port}/ws`, {headers: {Origin: 'https://untrusted.example'}});
  check(forbiddenOrigin.status === 403, 'Unrelated website origin was allowed');
  check(state.players.filter(p => p.id !== state.me).every(p => p.zones.Hand.every(c => c.hidden && Object.keys(c).length === 2)), 'Opponent hand details leaked');

  // A handshake itself must supply a snapshot even if the game is waiting and unchanged.
  const second = await connect();
  const recovered = await second.wait(m => m.type === 'state' && !m.loading);
  check(recovered.sessionId === state.sessionId, 'Reconnect changed the match');

  let response = await peer.send({type: 'action', action: 'ok', sessionId: 'old-session'}, state);
  check(response.type === 'error' && response.code === 'stale_session', 'Old-session action accepted');
  response = await peer.send({type: 'action', action: 'ok', revision: 0}, state);
  check(response.type === 'error' && response.code === 'stale_state', 'Stale action accepted');
  const beforeMalformed = peer.messages.length;
  peer.ws.send('{broken');
  response = await peer.wait(m => m.type === 'error', beforeMalformed);
  check(response.code === 'invalid_request', 'Malformed JSON did not get a structured error');
  if (process.env.FORGE_SMOKE_SCREENSHOT) {
    const edge = process.env.FORGE_EDGE_PATH || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
    const browser = spawn(edge, ['--headless=new', '--disable-gpu', '--no-first-run', '--window-size=1400,1000', '--virtual-time-budget=5000', `--screenshot=${process.env.FORGE_SMOKE_SCREENSHOT}`, `http://127.0.0.1:${port}/`], {windowsHide: true, stdio: 'ignore'});
    await new Promise((resolve, reject) => { browser.on('error', reject); browser.on('exit', code => code === 0 ? resolve() : reject(new Error('Screenshot browser failed'))); });
  }

  // Startup notices vary with the user's decks. Acknowledge messages until a real choice appears.
  let testedChoice = false, testedInput = false;
  const choiceDeadline = Date.now() + 60000;
  for (let step = 0; Date.now() < choiceDeadline && !testedInput; step++) {
    const start = peer.messages.length;
    peer.ws.send(JSON.stringify({type: 'hello'}));
    state = await peer.wait(m => m.type === 'state' && !m.loading, start);
    const ask = state.asks[0];
    if (!ask) {
      if (state.pendingDraws?.length) {
        await peer.send({type: 'action', action: 'draw_ack', id: state.pendingDraws[0]}, state);
        continue;
      }
      if (state.prompt.okEnabled && /keep/i.test(state.prompt.okLabel)) {
        response = await peer.send({type: 'action', action: 'ok'}, state);
        if (response.type === 'error' && response.code === 'stale_state') continue;
        check(response.type === 'ack' && response.code === 'dispatched', 'Keep-hand input was not dispatched');
        testedInput = true;
        break;
      }
      // Coin toss may require clicking a player even when the target list is empty.
      if (/portrait/i.test(state.prompt.message)) await peer.send({type: 'action', action: 'player', id: state.me}, state);
      else if (state.prompt.okEnabled) {
        response = await peer.send({type: 'action', action: 'ok'}, state);
        // Some Forge builds use a generic OK label for Keep. Reaching a dealt hand and
        // successfully dispatching its input is the real integration check.
        if (response.type === 'ack' && state.players.find(p => p.id === state.me).handCount > 0) {
          check(response.code === 'dispatched', 'Gameplay input was not dispatched');
          testedInput = true;
        }
      }
      await pause(500);
      continue;
    }
    if ((ask.kind === 'choose' || ask.kind === 'order') && !testedChoice) {
      response = await peer.send({type: 'answer', id: ask.id, value: [ask.options.length]}, state);
      check(response.type === 'error', 'Out-of-range decision answer accepted');
      const reconnected = await connect();
      const pending = await reconnected.wait(m => m.type === 'state' && !m.loading);
      check(pending.asks.some(a => a.id === ask.id), 'Invalid answer closed the pending decision');
      const selected = Array.from({length: ask.min}, (_, i) => i);
      response = await peer.send({type: 'answer', id: ask.id, value: selected}, state);
      check(response.type === 'ack' && response.code === 'answered', 'Valid answer rejected');
      await peer.wait(m => m.type === 'askClosed' && m.id === ask.id);
      response = await peer.send({type: 'answer', id: ask.id, value: selected}, state);
      check(response.type === 'error', 'Duplicate answer accepted');
      const after = await connect();
      const closed = await after.wait(m => m.type === 'state' && !m.loading);
      check(!closed.asks.some(a => a.id === ask.id), 'Reconnect resurrected a closed ask');
      testedChoice = true;
    } else if (ask.kind === 'choose' || ask.kind === 'order') {
      const selected = Array.from({length: ask.min}, (_, i) => i);
      response = await peer.send({type: 'answer', id: ask.id, value: selected}, state);
      check(response.type === 'ack', 'Startup choice was not accepted');
      await peer.wait(m => m.type === 'askClosed' && m.id === ask.id);
    } else if (ask.kind === 'message') {
      response = await peer.send({type: 'answer', id: ask.id, value: true}, state);
      check(response.type === 'ack', 'Startup notice could not be acknowledged');
      await peer.wait(m => m.type === 'askClosed' && m.id === ask.id);
    } else throw new Error(`Unexpected startup decision: ${ask.kind}`);
  }
  check(testedInput, 'Did not reach and keep an opening hand');
  response = await peer.send({type: 'answer', id: 2147483647, value: []}, state);
  check(response.type === 'error', 'Unknown decision ID accepted');
  console.log(`PASS: ${passed} live protocol checks against a three-player Commander match`);
} catch (error) {
  console.error(error);
  console.error('Java log tail:\n' + tail);
  process.exitCode = 1;
} finally {
  for (const peer of peers) peer.ws.close();
  child.kill();
  await Promise.race([new Promise(resolve => child.once('exit', resolve)), pause(3000)]);
  if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
}
