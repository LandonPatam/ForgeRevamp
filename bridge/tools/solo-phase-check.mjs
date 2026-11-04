// Real solo match: checked bot phases must wait for the human to pass priority.
// Only the JVM and sockets created by this check are stopped.
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';

const root = fileURLToPath(new URL('../', import.meta.url));
const probe = createServer();
await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
const port = probe.address().port;
await new Promise(resolve => probe.close(resolve));
const child = spawn('java', ['-Xmx3g', '-cp', 'target/classes;target/lib/*', 'forgeui.bridge.BridgeMain',
  '--assets', '../forge/forge-gui', '--port', String(port), '--opponents', '2'], {cwd: root, windowsHide: true});
let tail = '', ready = false, state, ws, counter = 0;
for (const stream of [child.stdout, child.stderr]) stream.on('data', data => {
  tail = (tail + data).slice(-6000);
  ready ||= tail.includes('Bridge ready:');
});
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const defaults = ['MAIN1', 'COMBAT_DECLARE_ATTACKERS', 'COMBAT_DECLARE_BLOCKERS', 'MAIN2'];
const seen = new Map();
const send = request => ws.send(JSON.stringify({protocolVersion: 2, sessionId: state.sessionId,
  revision: state.revision, requestId: `solo-${++counter}`, ...request}));
try {
  const deadline = Date.now() + 180000;
  while (!ready) {
    assert.equal(child.exitCode, null, tail);
    assert.ok(Date.now() < deadline, `Startup timed out: ${tail}`);
    await pause(200);
  }
  ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  ws.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.type === 'state' && !message.loading) state = message;
  };
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  while (Date.now() < deadline) {
    if (!state) { await pause(50); continue; }
    const current = state;
    const bot = current.game.activePlayer !== current.me;
    if (bot && defaults.includes(current.game.phaseKey) && current.prompt?.inputKind === 'InputPassPriority'
        && current.prompt.okEnabled && !current.stack?.length && !current.asks?.length) {
      const key = `${current.game.activePlayer}:${current.game.phaseKey}`;
      const turns = seen.get(key) ?? new Set();
      if (!turns.has(current.game.turn)) {
        await pause(450);
        ws.send(JSON.stringify({type: 'hello'}));
        await pause(200);
        assert.equal(state.game.turn, current.game.turn, 'Bot turn advanced without a human pass');
        assert.equal(state.game.phaseKey, current.game.phaseKey, 'Checked bot phase advanced without a human pass');
        assert.equal(state.prompt.inputKind, 'InputPassPriority', 'Bot stop lost its priority input');
        turns.add(current.game.turn);
        seen.set(key, turns);
        console.log(`  ok - bot ${key} waits for a pass on turn ${current.game.turn}`);
      }
    }
    const bots = state.players.filter(player => player.id !== state.me);
    if (bots.every(player => ['MAIN1', 'MAIN2'].every(phase => (seen.get(`${player.id}:${phase}`)?.size ?? 0) >= 2))) {
      console.log('PASS: Both bots pause at M1 and M2 across repeated turns');
      break;
    }
    if (state.asks?.length) {
      for (const ask of state.asks) {
        const value = ask.kind === 'choose' ? Array.from({length: ask.min}, (_, i) => i)
          : ask.kind === 'order' ? Array.from({length: ask.max}, (_, i) => i)
          : ask.kind === 'input' ? null : true;
        send({type: 'answer', id: ask.id, value});
      }
    } else if (state.pendingDraws?.length) send({type: 'action', action: 'draw_ack', id: state.pendingDraws[0].id ?? state.pendingDraws[0]});
    else if (state.prompt?.entities?.length && state.prompt.inputKind === 'InputSelectEntitiesFromList') send({type: 'action', action: 'player', id: state.prompt.entities[0].id});
    else if (state.prompt?.okEnabled) send({type: 'action', action: 'ok'});
    else if (state.prompt?.selectable?.length && state.prompt.inputKind !== 'InputPassPriority') {
      const chosen = (state.prompt.chosen ?? []).map(entry => entry.id ?? entry);
      const card = state.prompt.selectable.find(id => !chosen.includes(id));
      if (card !== undefined) send({type: 'action', action: 'card', id: card});
    }
    else if (state.prompt?.cancelEnabled) send({type: 'action', action: 'cancel'});
    await pause(150);
  }
  assert.ok(state?.players.filter(player => player.id !== state.me).every(player =>
    ['MAIN1', 'MAIN2'].every(phase => (seen.get(`${player.id}:${phase}`)?.size ?? 0) >= 2)),
  `Bot stops not reached: ${JSON.stringify([...seen].map(([key, turns]) => [key, [...turns]]))}; ${tail}`);
} catch (error) {
  console.error(error);
  process.exitCode = 1;
} finally {
  ws?.close();
  child.kill();
  // WebSocket keep-alive timers can otherwise retain Node after the owned JVM exits.
  setTimeout(() => process.exit(process.exitCode ?? 0), 1500);
}
