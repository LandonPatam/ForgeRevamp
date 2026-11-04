// Real Forge: two human seats and a bot. No router, library service or user decks.
import {spawn, spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {join, delimiter} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';

const root = fileURLToPath(new URL('../', import.meta.url));
const four = process.argv.includes('--four');
const response = process.argv.includes('--response');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const fixture = mkdtempSync(join(root, 'target', 'online-turn-'));
async function port() {
  const server = createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const result = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return result;
}
const hostPort = await port(), remotePort = await port();
const token = '0123456789abcdef'.repeat(4);
const deckFile = join(fixture, 'Priority.dck');
writeFileSync(deckFile, '[metadata]\nName=Online turns\n[Commander]\n1 Isamaru, Hound of Konda\n[Main]\n99 Plains\n');
const profile = name => ({name, avatar: 0, portrait: ''});
const setupFile = join(fixture, 'setup.json');
writeFileSync(setupFile, JSON.stringify({human: profile('Host'), bots: [{...profile('Bot'), mode: 'saved', deckFile}],
  remotePort, remotes: [{...profile('Friend'), token, deckFile},
    ...(four ? [{...profile('Friend 2'), token: 'f'.repeat(64), deckFile}] : [])]}));
const stateFile = join(fixture, 'combat.state');
// Forge can reorder nonhost seats when choosing the first player. Give every
// nonhost a blocker, then address the actual friend by their engine player ID.
writeFileSync(stateFile, `activeplayer=p0
activephase=MAIN1
turn=5
removesummoningsickness=true
p0life=40
p0battlefield=Grizzly Bears${response ? ';Forest' : ''}
p0hand=${response ? 'Giant Growth' : ''}
p0library=${Array(40).fill('Plains').join(';')}
p1life=40
p1battlefield=Hill Giant
p1hand=
p1library=${Array(40).fill('Plains').join(';')}
p2life=40
p2battlefield=Hill Giant
p2hand=
p2library=${Array(40).fill('Plains').join(';')}
${four ? `p3life=40\np3battlefield=Hill Giant\np3hand=\np3library=${Array(40).fill('Plains').join(';')}\n` : ''}
`.split('\n').filter(line => line && !line.endsWith('=')).join('\n'));
const javaSettings = spawnSync('java', ['-XshowSettings:properties', '-version'], {encoding: 'utf8', windowsHide: true});
const javaHome = javaSettings.stderr?.match(/^\s*java.home = (.+)$/m)?.[1].trim();
if (!javaHome) throw new Error('Cannot locate the JDK');
// Windows PATH may point at a launcher that spawns another JVM. Start the real
// executable so cleanup owns and stops the actual match process.
const child = spawn(join(javaHome, 'bin', process.platform === 'win32' ? 'java.exe' : 'java'), ['-Xmx3g', '-cp', ['target/classes', 'target/lib/*'].join(delimiter),
  'forgeui.bridge.BridgeMain', '--assets', '../forge/forge-gui', '--port', String(hostPort),
  '--deck-file', deckFile, '--setup-file', setupFile, '--opponents', '1', '--test-state', stateFile],
  {cwd: root, windowsHide: true});
let tail = '', counter = 0, checks = 0;
for (const stream of [child.stdout, child.stderr]) stream.on('data', data => { tail = (tail + data).slice(-7000); });
const peers = [];
const check = (value, message) => { assert.ok(value, message); checks++; console.log(`  ok - ${message}`); };
async function wait(predicate, label, ms = 20000) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error('Bridge exited');
    const result = predicate();
    if (result) return result;
    await pause(40);
  }
  throw new Error(`Timed out: ${label}; ${JSON.stringify(peers.map(p => ({game: p.state?.game, prompt: p.state?.prompt?.message, kind: p.state?.prompt?.inputKind, ok: p.state?.prompt?.okEnabled})))}`);
}
async function connect(number, auth) {
  const deadline = Date.now() + 120000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`Bridge exited during startup: ${tail}`);
    try {
      const ws = new WebSocket(`ws://127.0.0.1:${number}/ws`);
      const peer = {ws, messages: [], state: null};
      ws.onmessage = event => {
        const message = JSON.parse(event.data);
        peer.messages.push(message);
        if (message.type === 'state' && !message.loading) peer.state = message;
      };
      await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
      peers.push(peer);
      ws.send(JSON.stringify(auth ? {type: 'auth', token: auth} : {type: 'hello'}));
      return peer;
    } catch { await pause(300); }
  }
  throw new Error('Bridge startup timed out');
}
async function action(peer, action, extra = {}, expectedCode = null) {
  for (let tries = 0; tries < 40; tries++) {
    const s = peer.state, requestId = `turn-${++counter}`;
    peer.ws.send(JSON.stringify({type: 'action', action, ...extra, protocolVersion: 2,
      sessionId: s.sessionId, revision: s.revision, requestId}));
    const reply = await wait(() => peer.messages.find(m => m.requestId === requestId), action);
    if (reply.code === 'stale_state') { await pause(150); continue; }
    if (expectedCode) assert.equal(reply.code, expectedCode);
    else assert.equal(reply.type, 'ack', reply.message);
    await pause(180);
    return;
  }
  throw new Error('Never reached a stable input');
}
async function agreed(label) {
  await wait(() => peers.every(p => p.state) && peers.every(p =>
    JSON.stringify(p.state.game) === JSON.stringify(peers[0].state.game)), label);
  check(true, label);
}
try {
  const host = await connect(hostPort), friend = await connect(remotePort, token);
  if (four) await connect(remotePort, 'f'.repeat(64));
  console.log('  connected host and friend; completing opening decisions');
  await wait(() => peers.every(p => p.state), 'initial states', 120000);
  const openingDeadline = Date.now() + 60000;
  while (Date.now() < openingDeadline && host.state.game.turn !== 5) {
    for (const peer of peers) {
      const s = peer.state;
      if (s.asks?.length) throw new Error(`Unexpected opening ask: ${JSON.stringify(s.asks)}`);
      if (s.prompt.inputKind === 'InputSelectEntitiesFromList' && s.prompt.entities.length)
        await action(peer, 'player', {id: s.prompt.entities[0].id});
      else if (s.prompt.inputKind === 'InputConfirmMulligan' && s.prompt.okEnabled)
        await action(peer, 'ok');
    }
    await pause(100);
  }
  // The prepared state is applied after the real opening decisions.
  await wait(() => host.state?.game.turn === 5 && host.state.prompt?.inputKind === 'InputPassPriority', 'prepared host turn', 120000);
  await agreed('Both seats agree on the initial turn, active player and phase');
  check(!friend.state.prompt.okEnabled && !friend.state.prompt.cancelEnabled, 'The waiting friend has no stale phase buttons');
  await action(friend, 'ok', {}, 'invalid_action');
  await action(host, 'ok');
  await wait(() => host.state.prompt.inputKind === 'InputAttack', 'attack declaration');
  const bear = host.state.players.find(p => p.id === host.state.me).zones.Battlefield.find(c => c.name === 'Grizzly Bears');
  await action(host, 'attack', {id: bear.id, target: friend.state.me});
  check(host.state.combat.some(c => c.attacker === bear.id && c.defenderId === friend.state.me), 'Forge records the attack against the friend');
  await action(host, 'ok');
  if (response) {
    await wait(() => host.state.prompt.inputKind === 'InputPassPriority' && host.state.game.phaseKey === 'COMBAT_DECLARE_ATTACKERS', 'legal response after attackers');
    check(host.state.prompt.okEnabled, 'An affordable combat trick retains priority after attackers');
    await action(host, 'ok');
  }
  await wait(() => friend.state.prompt.inputKind === 'InputBlock', 'friend blocker declaration');
  await agreed('Both seats agree while the friend declares blockers');
  check(!host.state.prompt.okEnabled, 'The attacker has no stale declaration OK while the defender chooses');
  const giant = friend.state.players.find(p => p.id === friend.state.me).zones.Battlefield.find(c => c.name === 'Hill Giant');
  await action(friend, 'card', {id: bear.id});
  await action(friend, 'card', {id: giant.id});
  await action(friend, 'ok');
  if (response) {
    await wait(() => host.state.prompt.inputKind === 'InputPassPriority' && host.state.game.phaseKey === 'COMBAT_DECLARE_BLOCKERS', 'legal response after blockers');
    check(host.state.prompt.okEnabled, 'An affordable combat trick retains priority after blockers');
    await action(host, 'ok');
  }
  await wait(() => host.state.game.phaseKey === 'MAIN2' && host.state.prompt.inputKind === 'InputPassPriority', 'combat resolves without extra priority OKs');
  await agreed('Combat reaches M2 on both seats after one blocker confirmation');
  check(host.state.players.find(p => p.id === host.state.me).zones.Graveyard.some(c => c.id === bear.id), 'Forge resolves the block and kills the attacking bear');
  if (!response) {
    const controlledHumans = new Set([host.state.me]);
    const deadline = Date.now() + 45000;
    while (Date.now() < deadline && Math.min(...peers.map(p => p.state.game.turn)) < 9) {
      await agreedSilently();
      for (const peer of peers) {
        const s = peer.state;
        if (s.pendingDraws?.length) { await action(peer, 'draw_ack', {id: s.pendingDraws[0]}); continue; }
        if (s.game.activePlayer !== s.me) {
          assert.ok(s.prompt.inputKind !== 'InputPassPriority' && (s.prompt.inputKind === 'InputBlock' || !s.prompt.okEnabled), `Idle seat ${s.me} has a priority OK during ${s.game.activePlayer}'s ${s.game.phaseKey}`);
          if (s.prompt.inputKind === 'InputBlock' && s.prompt.okEnabled) await action(peer, 'ok');
          continue;
        }
        controlledHumans.add(s.me);
        if (s.prompt.okEnabled) await action(peer, 'ok');
        else if (s.prompt.selectable?.length) {
          const chosen = (s.prompt.chosen ?? []).map(c => c.id ?? c);
          const id = s.prompt.selectable.find(id => !chosen.includes(id));
          if (id !== undefined) await action(peer, 'card', {id});
        }
      }
      await pause(100);
    }
    // The bot can finish between snapshot ticks. Reaching turn 9 necessarily crosses
    // its turn; require that every human also took their own turn in the interval.
    check(Math.min(...peers.map(p => p.state.game.turn)) >= 9 && controlledHumans.size === peers.length,
      'Every human follows host, bot and friend turns with no idle priority clicks');
  }
  console.log(`online-turn-check: ${checks} checks passed`);
} catch (error) {
  console.error(`online-turn-check FAILED: ${error.stack}\n${tail}`);
  process.exitCode = 1;
} finally {
  for (const peer of peers) peer.ws.close();
  child.kill();
  await Promise.race([new Promise(resolve => child.exitCode !== null || child.signalCode !== null ? resolve() : child.once('exit', resolve)), pause(2000)]);
  rmSync(fixture, {recursive: true, force: true});
  process.exit(process.exitCode ?? 0);
}
async function agreedSilently() {
  await wait(() => peers.every(p => JSON.stringify(p.state.game) === JSON.stringify(peers[0].state.game)), 'turn agreement');
}
