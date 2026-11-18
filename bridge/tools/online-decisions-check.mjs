// A prepared two-human match over the real bridge sockets. No lobby or router is needed.
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdtempSync, rmSync, rmdirSync, writeFileSync} from 'node:fs';
import {delimiter, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const bridge = join(root, 'bridge');
const build = resolve(root, process.argv[2] || 'bridge/target');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const children = [];
const sockets = [];
let sequence = 0;
let log = '';

async function waitFor(read, name, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = read();
    if (value) return value;
    await pause(40);
  }
  throw new Error(`Timed out waiting for ${name}`);
}

async function reservePort() {
  const server = createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return {port: server.address().port, release: () => new Promise(resolve => server.close(resolve))};
}

async function connect(port, token) {
  const socket = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  sockets.push(socket);
  const peer = {socket, messages: [], state: null};
  socket.onmessage = event => {
    const message = JSON.parse(event.data);
    peer.messages.push(message);
    if (message.type === 'state' && !message.loading) peer.state = message;
  };
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  if (token) socket.send(JSON.stringify({type: 'auth', token}));
  return peer;
}

async function request(peer, state, message) {
  const requestId = `decision-${++sequence}`;
  peer.socket.send(JSON.stringify({protocolVersion: 2, sessionId: state.sessionId, revision: state.revision, requestId, ...message}));
  return waitFor(() => peer.messages.find(reply => reply.requestId === requestId), message.action || message.type, 5000);
}

async function act(peer, action, extra = {}) {
  for (let attempt = 0; attempt < 10; attempt++) {
    const state = peer.state;
    const reply = await request(peer, state, {type: 'action', action, ...extra});
    if (reply.type === 'ack') return;
    assert.equal(reply.code, 'stale_state', reply.message);
    await waitFor(() => peer.state.revision > state.revision, 'a fresh revision');
  }
  throw new Error(`Could not submit ${action}`);
}

function ownZone(peer, zone) {
  return peer.state.players.find(player => player.id === peer.state.me).zones[zone];
}

async function driveUntil(peers, ready, name) {
  return waitFor(() => {
    if (ready()) return true;
    for (const peer of peers) {
      const state = peer.state;
      if (!state || state.asks.length || state.revision === peer.lastDriven) continue;
      const draw = state.pendingDraws?.[0];
      const portrait = state.prompt.inputKind === 'InputSelectEntitiesFromList' && state.prompt.entities[0];
      const action = draw !== undefined ? {action: 'draw_ack', id: draw.id ?? draw}
        : portrait ? {action: 'player', id: portrait.id}
        : state.prompt.okEnabled ? {action: 'ok'} : null;
      if (!action) continue;
      peer.lastDriven = state.revision;
      peer.socket.send(JSON.stringify({protocolVersion: 2, sessionId: state.sessionId, revision: state.revision,
        requestId: `drive-${++sequence}`, type: 'action', ...action}));
    }
    return false;
  }, name, 60000);
}

async function payAndCast(peer, spell, land, count) {
  for (let i = 0; i < count; i++) {
    const source = ownZone(peer, 'Battlefield').find(card => card.name === land && !card.tapped);
    assert.ok(source, `Expected an untapped ${land}`);
    await act(peer, 'card', {id: source.id});
    await waitFor(() => ownZone(peer, 'Battlefield').some(card => card.id === source.id && card.tapped), `tapped ${land}`);
  }
  const card = ownZone(peer, 'Hand').find(card => card.name === spell);
  assert.ok(card, `Expected ${spell} in hand`);
  await act(peer, 'card', {id: card.id});
}

async function submitOrder(peer, names) {
  const ask = peer.state.asks[0];
  assert.equal(ask.kind, 'order');
  const order = names.map(name => ask.options.findIndex(option => option.card.name === name));
  assert.equal(ask.options.length, order.length);
  assert.ok(order.every(index => index >= 0));
  assert.equal((await request(peer, peer.state, {type: 'answer', id: ask.id, value: order})).type, 'ack');
  return ask.id;
}

const directory = mkdtempSync(join(bridge, 'target', 'decision-fixture-'));
try {
  const [hostPort, remotePort] = await Promise.all([reservePort(), reservePort()]);
  const deck = join(directory, 'Fixture.dck');
  const setup = join(directory, 'setup.json');
  const token = 'online-decision-fixture';
  writeFileSync(deck, "[metadata]\nName=Decision fixture\n[Commander]\n1 Atraxa, Praetors' Voice|PF26|1\n[Main]\n99 Forest|SOS|1\n");
  writeFileSync(setup, JSON.stringify({human: {name: 'Host', avatar: 1}, bots: [], remotePort: remotePort.port,
    remotes: [{name: 'Guest', avatar: 2, token, deckFile: deck}]}));
  const javaSettings = spawnSync('java', ['-XshowSettings:properties', '-version'], {encoding: 'utf8', windowsHide: true});
  const javaHome = javaSettings.stderr?.match(/^\s*java.home = (.+)$/m)?.[1].trim();
  assert.ok(javaHome, 'Cannot locate Java');
  await Promise.all([hostPort.release(), remotePort.release()]);
  const engine = spawn(join(javaHome, 'bin', process.platform === 'win32' ? 'java.exe' : 'java'),
    ['-Xmx4g', '-cp', [join(build, 'classes'), join(build, 'lib', '*')].join(delimiter), 'forgeui.bridge.BridgeMain',
      '--assets', '../forge/forge-gui', '--port', String(hostPort.port), '--deck-file', deck, '--opponents', '0',
      '--setup-file', setup, '--test-state', 'tools/fixtures/online-decisions.state'],
    {cwd: bridge, windowsHide: true});
  children.push(engine);
  for (const stream of [engine.stdout, engine.stderr]) stream.on('data', value => { log = (log + value).slice(-12000); });
  await waitFor(() => log.includes('Bridge ready:'), 'bridge startup', 90000);
  const host = await connect(hostPort.port);
  let guest = await connect(remotePort.port, token);
  await driveUntil([host, guest], () => log.includes('Test state applied:') && host.state?.prompt?.inputKind === 'InputPassPriority'
    && host.state.game.phaseKey === 'MAIN1' && ownZone(host, 'Hand').some(card => card.name === 'Elvish Visionary'), 'prepared main phase');

  await payAndCast(host, 'Elvish Visionary', 'Forest', 2);
  await driveUntil([host, guest], () => host.state?.asks.some(ask => ask.kind === 'order'), "active player's ordering");
  assert.equal(guest.state.asks.length, 0, 'The guest cannot see the host ordering decision');
  const hostOrder = ["Ajani's Welcome", 'Soul Warden', 'Elvish Visionary'];
  await submitOrder(host, hostOrder);
  await driveUntil([host], () => guest.state?.asks.some(ask => ask.kind === 'order'), "nonactive player's ordering");
  assert.equal(host.state.asks.length, 0, 'The host cannot see the guest ordering decision');
  const pendingOrder = guest.state.asks[0];
  const prior = guest.state;
  guest.socket.close();
  await waitFor(() => host.state.absentPlayers?.includes('Guest'), 'guest disconnect');
  guest = await connect(remotePort.port, token);
  const resumed = await waitFor(() => guest.state?.asks.find(ask => ask.id === pendingOrder.id), 'the same ordering after reconnect');
  assert.equal(guest.state.sessionId, prior.sessionId);
  assert.equal(guest.state.me, prior.me);
  assert.deepEqual(resumed.options, pendingOrder.options);
  const guestOrder = ['Auriok Champion', 'Essence Warden'];
  const closedOrder = await submitOrder(guest, guestOrder);
  const stacked = await waitFor(() => host.state.stack.length === 5 && host.state.stack, 'all five triggers on the stack');
  assert.deepEqual(stacked.map(item => item.sourceName), [...guestOrder, ...hostOrder]);
  console.log('PASS: each seat orders only its own triggers, the pending order survives reconnect, and the nonactive triggers resolve first');

  await driveUntil([host, guest], () => guest.state?.game.activePlayer === guest.state.me
    && guest.state.game.phaseKey === 'MAIN1' && guest.state.prompt.inputKind === 'InputPassPriority'
    && guest.state.pendingDraws.length === 0, "guest's main phase");
  await payAndCast(guest, 'Preordain', 'Island', 1);
  await driveUntil([host, guest], () => guest.state?.asks.some(ask => ask.kind === 'scry'), "guest's scry");
  const scry = guest.state.asks[0];
  assert.deepEqual(scry.options.map(option => option.card.name), ['Craw Wurm', 'Serra Angel']);
  assert.equal(host.state.asks.length, 0);
  assert.ok(host.messages.every(message => !JSON.stringify(message).includes('Craw Wurm') && !JSON.stringify(message).includes('Serra Angel')),
    'Neither a host snapshot nor a host event reveals the guest scry cards');
  const replay = await request(guest, prior, {type: 'answer', id: closedOrder, value: [0, 1]});
  assert.equal(replay.type, 'error', 'The completed ordering answer cannot reach the replacement decision');
  assert.equal(guest.state.asks[0].id, scry.id);
  assert.equal((await request(guest, guest.state, {type: 'answer', id: scry.id, value: {top: [1], bottom: [0]}})).type, 'ack');
  await driveUntil([host, guest], () => ownZone(guest, 'Hand').some(card => card.name === 'Serra Angel'), 'the chosen card drawn by Preordain');
  console.log('PASS: guest scry stays private, rejects the old answer, and draws the exact selected card');
} catch (error) {
  console.error(error);
  console.error(log);
  process.exitCode = 1;
} finally {
  for (const socket of sockets) socket.close();
  for (const child of children) {
    if (child.exitCode === null) {
      const finished = new Promise(resolve => child.once('exit', resolve));
      child.kill();
      await finished;
    }
  }
  rmSync(join(directory, 'setup.json'), {force: true});
  rmSync(join(directory, 'Fixture.dck'), {force: true});
  rmdirSync(directory);
}
