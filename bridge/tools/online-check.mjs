// Hosts a real lobby in an isolated library service, joins it over the online port, starts a real Forge
// match and checks seat isolation, hidden information, tokens, reconnect and leaving. Stops only its own processes.
import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdtempSync, rmSync, readFileSync, existsSync, writeFileSync } from 'node:fs';
import { join, resolve, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const bridgeRoot = fileURLToPath(new URL('../', import.meta.url));
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const probe = createServer();
await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
const libraryPort = String(probe.address().port);
await new Promise(resolve => probe.close(resolve));
const fixture = mkdtempSync(join(bridgeRoot, 'target', 'online-fixture-'));
// No affordable off-turn spells or abilities: idle seats must never gate these turns.
writeFileSync(join(fixture, 'Priority.dck'), "[metadata]\nName=Online priority fixture\n[Commander]\n1 Atraxa, Praetors' Voice|PF26|1\n[Main]\n99 Forest|SOS|1\n");
// --mac-app exercises the exact shipped service/classes/assets and bundled JVM, with isolated test data.
const option = name => { const i = process.argv.indexOf(name); return i < 0 ? undefined : process.argv[i + 1]; };
const macApp = option('--mac-app');
const architecture = option('--arch') || (process.arch === 'arm64' ? 'arm64' : 'x86_64');
if (!['arm64', 'x86_64'].includes(architecture)) throw Error('Unsupported Mac architecture');
const payload = macApp ? resolve(macApp, 'Contents/Resources') : null;
const javaSettings = payload ? null : spawnSync('java', ['-XshowSettings:properties', '-version'], {encoding: 'utf8', windowsHide: true});
const javaHome = payload ? join(payload, 'runtime', architecture, 'Contents/Home') : javaSettings.stderr?.match(/^\s*java.home = (.+)$/m)?.[1].trim();
if (!javaHome) throw Error('Cannot locate Java');
const classpath = payload ? [join(payload, 'service/classes'), join(payload, 'service/lib/*')].join(delimiter) : ['target/classes', 'target/lib/*'].join(delimiter);
const child = spawn(join(javaHome, 'bin', process.platform === 'win32' ? 'java.exe' : 'java'),
  ['-Xmx4g', '-cp', classpath, 'forgeui.bridge.LibraryMain', '--assets', payload ? join(payload, 'forge-gui') : '../forge/forge-gui',
    '--port', libraryPort, '--library-root', fixture, '--data-dir', fixture, '--parent-pid', String(process.pid)],
  {cwd: bridgeRoot, windowsHide: true});
let tail = '';
for (const stream of [child.stdout, child.stderr]) stream.on('data', data => { tail = (tail + data).slice(-6000); });
child.on('error', error => { tail += String(error); });
const remoteAddress = option('--host-address') || '127.0.0.1';
console.log(`Online check: ${payload || 'source classes'}; Java ${architecture}; online address ${remoteAddress}`);

let passed = 0;
const check = (value, message) => { assert.ok(value, message); passed++; console.log(`  ok - ${message}`); };
const sockets = [];

function open(url) {
  const ws = new WebSocket(url);
  sockets.push(ws);
  const messages = [];
  const peer = {ws, messages, closed: false,
    async wait(predicate, what = 'message', ms = 60000) {
      const deadline = Date.now() + ms;
      while (Date.now() < deadline) {
        const found = messages.findLast(predicate);
        if (found) return found;
        await pause(25);
      }
      throw new Error(`Timed out waiting for ${what}`);
    },
    send(message) { ws.send(JSON.stringify(message)); },
  };
  ws.onmessage = event => messages.push(JSON.parse(event.data));
  ws.onclose = () => { peer.closed = true; };
  return new Promise((resolve, reject) => {
    ws.onopen = () => resolve(peer);
    ws.onerror = () => reject(new Error(`Could not connect to ${url}`));
  });
}

let library, nextRequest = 0;
async function call(op, args = {}) {
  const requestId = ++nextRequest;
  library.send({op, requestId, ...args});
  const reply = await library.wait(m => m.requestId === requestId, op, 120000);
  if (!reply.ok) throw new Error(`${op}: ${reply.error}`);
  return reply.result;
}
async function callRejected(op, args = {}) {
  try { await call(op, args); return null; } catch (error) { return error.message; }
}

// One move for a seat: answer its decisions, take a pending draw, click a required portrait, or press OK.
let driven = 0;
function step(peer) {
  const state = peer.messages.findLast(m => m.type === 'state' && !m.loading && m.players?.length >= 2);
  if (!state || peer.lastRevision === state.revision) return state;
  peer.lastRevision = state.revision;
  const send = message => peer.send({protocolVersion: 2, sessionId: state.sessionId, revision: state.revision, requestId: `d${++driven}`, ...message});
  if (state.asks?.length) {
    for (const ask of state.asks) {
      if (peer.answered?.has(ask.id)) continue;
      (peer.answered ??= new Set()).add(ask.id);
      send({type: 'answer', id: ask.id, value: fallback(ask)});
    }
    return state;
  }
  const draw = state.pendingDraws?.[0];
  if (draw !== undefined) send({type: 'action', action: 'draw_ack', id: draw.id ?? draw});
  else if (state.prompt?.entities?.length && state.prompt.inputKind === 'InputSelectEntitiesFromList') send({type: 'action', action: 'player', id: state.prompt.entities[0].id});
  else if (state.prompt?.okEnabled) send({type: 'action', action: 'ok'});
  else if (state.prompt?.selectable?.length && state.prompt.inputKind !== 'InputPassPriority') {
    // A required card choice, such as a cleanup discard.
    const chosen = (state.prompt.chosen ?? []).map(entry => entry.id ?? entry);
    const card = state.prompt.selectable.find(id => !chosen.includes(id));
    if (card !== undefined) send({type: 'action', action: 'card', id: card});
  } else if (state.prompt?.cancelEnabled) send({type: 'action', action: 'cancel'});
  return state;
}

// Plays the given seats forward until the game reaches a later turn.
async function drive(peers, untilTurn, ms = 180000) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    for (const peer of peers) {
      const state = step(peer);
      if (state?.game?.turn >= untilTurn || state?.game?.gameOver) return true;
      // A stale click is refused with a fresh snapshot; allow the same revision to be tried again later.
      if (peer.messages.at(-1)?.type === 'error') peer.lastRevision = undefined;
    }
    await pause(120);
  }
  for (const peer of peers) {
    const state = peer.messages.findLast(m => m.type === 'state' && !m.loading);
    console.log('stuck at', JSON.stringify({turn: state?.game?.turn, prompt: state?.prompt?.message, kind: state?.prompt?.inputKind, ok: state?.prompt?.okEnabled, asks: state?.asks?.length, draws: state?.pendingDraws}), JSON.stringify(peer.messages.filter(m => m.type === 'error').slice(-2)));
  }
  return false;
}

function fallback(ask) {
  if (ask.kind === 'choose') return Array.from({length: ask.min}, (_, i) => i);
  if (ask.kind === 'order') return Array.from({length: ask.max}, (_, i) => i);
  if (ask.kind === 'distribute') return ask.options.map((_, i) => i === 0 ? ask.amount - (ask.atLeastOne ? ask.options.length - 1 : 0) : (ask.atLeastOne ? 1 : 0));
  if (ask.kind === 'input') return null;
  return true;
}

async function action(peer, name, extra = {}) {
  for (let tries = 0; tries < 30; tries++) {
    const state = peer.messages.findLast(m => m.type === 'state' && !m.loading);
    const requestId = `opening-${++driven}`;
    peer.send({type: 'action', action: name, ...extra, protocolVersion: 2, sessionId: state.sessionId, revision: state.revision, requestId});
    const reply = await peer.wait(m => m.requestId === requestId, name, 5000);
    if (reply.type === 'ack') return;
    if (reply.code !== 'stale_state') throw new Error(reply.message);
    await pause(100);
  }
  throw new Error(`Could not submit ${name} against a stable opening snapshot`);
}

const owner = 'online-check-owner-identity';
const human = {name: 'Host Player', avatar: 1, portrait: ''};
const bot = {name: 'Bot 1', avatar: 2, portrait: '', mode: 'randomPrecon', deckId: ''};

try {
  const deadline = Date.now() + 180000;
  while (!library) {
    if (child.exitCode !== null) throw new Error('Library exited during startup');
    if (Date.now() > deadline) throw new Error('Library startup timed out');
    try { library = await open(`ws://127.0.0.1:${libraryPort}/ws`); } catch { await pause(500); }
  }
  const listing = await call('list');
  const decks = listing.decks;
  const deck = decks.find(d => d.source === 'precon' && d.legal);
  const priorityDeck = decks.find(d => d.id === 'Priority.dck' && d.legal);
  if (!priorityDeck) console.log('Priority fixture:', JSON.stringify(decks.filter(d => d.source !== 'precon')), JSON.stringify(listing.warnings));
  check(priorityDeck, 'A legal no-response deck is available for phase progression checks');
  check(deck, 'A legal Commander precon is available for both players');

  // Hosting
  check((await call('lobby.status')).hosting === false, 'Not hosting before asked to');
  const hosted = await call('lobby.host', {discover: false, config: {human, bots: [bot]}});
  check(hosted.hosting && hosted.port > 0, `Hosting opens the online port (${hosted.port})`);
  const onlineUrl = `ws://${remoteAddress}:${hosted.port}/ws`;
  check((await callRejected('lobby.host', {discover: false, config: {human, bots: [bot]}}))?.includes('already hosting'), 'A second host request is refused, not duplicated');

  // The exposed port serves no files and refuses browsers.
  check((await fetch(`http://127.0.0.1:${hosted.port}/`)).status === 404, 'Online port serves no files');
  check((await fetch(`http://127.0.0.1:${hosted.port}/ws`, {headers: {Origin: `http://127.0.0.1:${hosted.port}`}})).status === 403, 'Online port refuses browser origins');

  // Joining
  const {deckData, version} = await call('lobby.deckText', {id: deck.id});
  check(version === 5, 'Lobby portrait changes use online protocol version 5');
  const joinMessage = (name, extra = {}) => ({type: 'join', version, name, avatar: 0, portrait: '', deckData, ...extra});
  const wrongBuild = await open(onlineUrl);
  wrongBuild.send(joinMessage('Old build', {version: 999}));
  check((await wrongBuild.wait(m => m.type === 'rejected', 'version rejection')).message.includes('same build'), 'A mismatched build is told plainly');
  const badDeck = await open(onlineUrl);
  badDeck.send(joinMessage('Bad deck', {deckData: Buffer.from('[metadata]\nName=Empty\n[Main]\n1 Mountain\n').toString('base64')}));
  check((await badDeck.wait(m => m.type === 'rejected', 'deck rejection')).message.includes('rejected your deck'), 'An illegal deck is rejected by the host');

  const friend = await open(onlineUrl);
  friend.send(joinMessage('Friend'));
  const lobby = await friend.wait(m => m.type === 'lobby', 'lobby update');
  check(lobby.roster.length === 3 && lobby.open === 1, 'Joining fills an open seat with no host action');
  check(lobby.roster.map(r => r.kind).join() === 'host,bot,player', 'Roster shows host, bot and player');
  const status = await call('lobby.status');
  check(status.players.length === 1 && status.players[0].name === 'Friend' && status.players[0].deck, 'Host sees the player and their deck');
  check(!JSON.stringify(status.players).includes('deckFile'), 'Host status exposes no server file paths');

  const second = await open(onlineUrl);
  second.send(joinMessage('Friend'));
  const secondLobby = await second.wait(m => m.type === 'lobby', 'second lobby update');
  check(secondLobby.roster.at(-1).name === 'Friend 2', 'A duplicate name is made unique');
  check(secondLobby.open === 0, 'The last seat is now taken');
  check((await callRejected('lobby.config', {config: {human, bots: [bot, {...bot, name: 'Extra bot'}]}}))?.includes('taken'), 'Adding a bot to a full table is refused');
  const third = await open(onlineUrl);
  third.send(joinMessage('Too many'));
  check((await third.wait(m => m.type === 'rejected', 'full rejection')).message.includes('full'), 'A full lobby refuses another player');
  friend.messages.length = 0;
  second.ws.close();
  await friend.wait(m => m.type === 'lobby' && m.open === 1, 'seat reopening', 5000);
  check(true, 'A player leaving reopens their seat');

  const kicked = await open(onlineUrl);
  kicked.send(joinMessage('Removed player'));
  const kickedLobby = await kicked.wait(m => m.type === 'lobby', 'kick test lobby');
  friend.messages.length = 0;
  await call('lobby.kick', {id: kickedLobby.you});
  check((await kicked.wait(m => m.type === 'rejected', 'kick notice')).message.includes('removed'), 'The host can remove a player');
  await friend.wait(m => m.type === 'lobby' && m.open === 1, 'seat reopening after kick');
  check(true, 'Removing a player frees their seat');

  // Windows decks use CRLF; the wire format must preserve UTF-8 names and deck bytes.
  const windowsText = Buffer.from(deckData, 'base64').toString('utf8').replace(/^Name=.*$/m, 'Name=Windows CRLF – Zoë').replace(/\r?\n/g, '\r\n');
  const windowsData = Buffer.from(windowsText, 'utf8').toString('base64');
  friend.send({type: 'deck', deckData: windowsData});
  await friend.wait(m => m.type === 'lobby' && m.roster.some(p => p.deck === 'Windows CRLF – Zoë'), 'Windows-style deck change');
  check((await call('lobby.status')).players[0].deck === 'Windows CRLF – Zoë', 'Deck changes accept Windows CRLF and UTF-8 names');
  friend.send({type: 'deck', deckData: Buffer.from('[metadata]\nName=Invalid replacement\n[Main]\n1 Mountain\n').toString('base64')});
  await friend.wait(m => m.type === 'rejected', 'invalid replacement rejection');
  check((await call('lobby.status')).players[0].deck === 'Windows CRLF – Zoë', 'An invalid replacement keeps the accepted deck in the roster');

  // A joined player can change their portrait in the lobby without leaving.
  friend.send({type: 'profile', avatar: 17, portrait: ''});
  const repainted = await friend.wait(m => m.type === 'lobby' && m.roster.some(p => p.kind === 'player' && p.name === 'Friend' && p.avatar === 17), 'portrait change');
  check(repainted.roster.find(p => p.name === 'Friend').avatar === 17, 'A joined player changes their portrait in the lobby');
  check((await call('lobby.status')).players[0].avatar === 17, 'The host sees the new portrait');
  friend.send({type: 'profile', avatar: 999, portrait: ''});
  await friend.wait(m => m.type === 'rejected' && m.message.includes('portrait'), 'invalid portrait rejection');
  check((await call('lobby.status')).players[0].avatar === 17, 'An invalid portrait keeps the accepted one');

  const fourth = await open(onlineUrl);
  fourth.send(joinMessage('Fourth seat'));
  await fourth.wait(m => m.type === 'lobby' && m.roster.length === 4, 'four-seat roster');
  check(true, 'A four-player roster contains the host, a bot and two joined people');

  // Starting: the online port is handed to the match process.
  const startArgs = {owner, id: deck.id, launchKey: 'online-check-launch-key', setup: {human, bots: [bot]}};
  check((await callRejected('match.start', startArgs))?.includes('press PLAY'), 'Starting is refused while players are not ready');
  await call('lobby.ready', {ready: true});
  check((await callRejected('match.start', startArgs))?.includes('press PLAY'), 'The host cannot start without the friend pressing PLAY');
  friend.messages.length = 0;
  friend.send({type: 'ready', ready: true});
  await friend.wait(m => m.type === 'lobby' && m.roster.some(p => p.name === 'Friend' && p.ready), 'friend ready before fourth seat');
  check((await callRejected('match.start', startArgs))?.includes('press PLAY'), 'Every joined human must ready, including the fourth seat');
  fourth.send({type: 'ready', ready: true});
  await friend.wait(m => m.type === 'lobby' && m.allReady, 'all three humans ready');
  check((await call('lobby.status')).players[0].ready, 'The host sees the friend ready');
  check((await call('lobby.config', {config: {human, bots: [bot]}})).allReady, 'Unchanged settings preserve readiness during polling');
  friend.messages.length = 0;
  friend.send({type: 'deck', deckData: windowsData});
  await friend.wait(m => m.type === 'lobby' && !m.allReady && m.roster.every(p => !p.ready), 'deck resets readiness');
  check(!(await call('lobby.status')).hostReady, 'Changing a deck resets everyone, including the host');
  friend.messages.length = 0;
  friend.send({type: 'ready', ready: true});
  await friend.wait(m => m.type === 'lobby' && !m.allReady && m.roster.some(p => p.kind === 'player' && p.ready), 'friend readies first');
  check((await callRejected('match.start', startArgs))?.includes('press PLAY'), 'A ready friend cannot bypass an unready host');
  fourth.messages.length = 0;
  fourth.send({type: 'ready', ready: true});
  await fourth.wait(m => m.type === 'lobby' && m.roster.filter(p => p.kind === 'player').every(p => p.ready), 'both friends ready before host');
  check((await call('lobby.ready', {ready: true})).allReady, 'Either readiness order works; bots need no confirmation');
  await call('match.start', {owner, id: deck.id, launchKey: 'online-check-launch-key', setup: {human, bots: [bot]}});
  const start = await friend.wait(m => m.type === 'start', 'start message');
  const fourthStart = await fourth.wait(m => m.type === 'start', 'fourth seat start');
  check(start.token?.length === 64 && start.port === hosted.port, 'The joined player receives a seat token');
  check((await call('lobby.status')).hosting === false, 'The lobby closes once the match starts');
  let ready;
  for (let tries = 0; tries < 400 && !ready; tries++) {
    const state = await call('match.status', {owner});
    if (state.state === 'failed') throw new Error(state.error);
    if (state.state === 'ready') ready = state; else await pause(300);
  }
  check(ready, 'Forge reports the online match ready');
  const setup = JSON.parse(readFileSync(join(fixture, 'app-sessions', `${ready.session}.setup.json`), 'utf8'));
  check(readFileSync(setup.remotes[0].deckFile, 'utf8') === windowsText, 'Rejecting a replacement preserves the accepted deck bytes used by the match');

  // Seat access
  const seatDeadline = Date.now() + 30000;
  let stranger;
  while (!stranger && Date.now() < seatDeadline) { try { stranger = await open(onlineUrl); } catch { await pause(250); } }
  check(stranger, 'The match process took over the online port');
  stranger.send({type: 'auth', token: 'f'.repeat(64)});
  await pause(600);
  check(stranger.closed && !stranger.messages.some(m => m.type === 'state'), 'A wrong token is disconnected without seeing the game');
  const unauthenticated = await open(onlineUrl);
  unauthenticated.send({type: 'hello'});
  await pause(600);
  check(!unauthenticated.messages.some(m => m.type === 'state'), 'No state before a seat token');

  const host = await open(ready.url);
  let player = await open(onlineUrl);
  player.send({type: 'auth', token: start.token});
  const fourthPlayer = await open(onlineUrl);
  fourthPlayer.send({type: 'auth', token: fourthStart.token});
  const isGame = m => m.type === 'state' && !m.loading && m.players?.length === 4;
  const hostState = await host.wait(isGame, 'host game state');
  const playerState = await player.wait(isGame, 'player game state');
  const fourthState = await fourthPlayer.wait(isGame, 'fourth seat game state');
  check(fourthState.me !== playerState.me && fourthState.me !== hostState.me, 'The fourth seat connects to its own player in a real four-player match');
  check(hostState.me !== playerState.me, 'Each seat is its own player');
  const name = (state, id) => state.players.find(p => p.id === id).name;
  check(name(hostState, hostState.me) === 'Host Player' && name(playerState, playerState.me) === 'Friend', 'Seats map to the right names');
  await host.wait(m => isGame(m) && m.tableReady, 'host table readiness before any acknowledgment');
  await player.wait(m => isGame(m) && m.tableReady, 'friend table readiness before any acknowledgment');
  check(true, 'Every device can load the table before anyone acknowledges the first prompt');
  // Forge can warn about a generated bot deck before it performs the toss.
  // Resolve only those information messages; leave the actual starting choice open.
  const tossDeadline = Date.now() + 15000;
  while (Date.now() < tossDeadline && ![host, player, fourthPlayer].every(peer => peer.messages.findLast(isGame)?.startingToss)) {
    for (const peer of [host, player, fourthPlayer]) {
      if (peer.messages.findLast(isGame)?.asks?.some(ask => ask.kind === 'message')) step(peer);
      if (peer.messages.at(-1)?.type === 'error') peer.lastRevision = undefined;
    }
    await pause(120);
  }
  const hostToss = await host.wait(m => isGame(m) && m.startingToss, 'host shared coin toss');
  const friendToss = await player.wait(m => isGame(m) && m.startingToss, 'friend shared coin toss');
  check(hostToss.startingToss.id === friendToss.startingToss.id && hostToss.startingToss.winnerId === friendToss.startingToss.winnerId && hostToss.startingToss.heads === friendToss.startingToss.heads, 'Every seat receives the same real Forge coin toss and winner');

  // Hidden information, in both directions, across the whole opening.
  const hiddenFrom = (state, other) => state.players.find(p => p.id === other).zones.Hand.every(c => c.hidden && Object.keys(c).length === 2);
  let bothHands = false;
  for (let tries = 0; tries < 400 && !bothHands; tries++) {
    const a = host.messages.findLast(isGame), b = player.messages.findLast(isGame);
    assert.ok(hiddenFrom(a, b.me), 'Friend\'s hand leaked to the host');
    assert.ok(hiddenFrom(b, a.me), 'Host\'s hand leaked to the friend');
    bothHands = a.players.find(p => p.id === a.me).zones.Hand.some(c => !c.hidden) && b.players.find(p => p.id === b.me).zones.Hand.some(c => !c.hidden);
    if (!bothHands) {
      // Only the coin-toss choice may be made here; mulligans stay open so a hand remains on show.
      for (const peer of [host, player, fourthPlayer]) {
        const state = peer.messages.findLast(isGame);
        if (state.prompt?.inputKind === 'InputSelectEntitiesFromList' || state.asks?.some(ask => ask.kind === 'message')) step(peer);
      }
      await pause(150);
    }
  }
  if (!bothHands) for (const [label, peer] of [['host', host], ['player', player]]) {
    const st = peer.messages.findLast(isGame);
    console.log(label, JSON.stringify({prompt: st.prompt?.message, kind: st.prompt?.inputKind, ok: st.prompt?.okEnabled, entities: st.prompt?.entities, asks: st.asks?.map(a => [a.kind, a.title]), counts: st.players.map(p => [p.name, p.zones.Hand.length]), first: st.players.find(p => p.id === st.me).zones.Hand[0]}).slice(0, 700), JSON.stringify(peer.messages.filter(m => m.type === 'error').slice(-2)));
  }
  check(bothHands, 'Both players see only their own hand');
  const chosenStart = await player.wait(m => isGame(m) && m.startingToss?.choosing === false, 'shared starting player result');
  check(chosenStart.players.some(p => p.id === chosenStart.startingToss.firstId && p.name === chosenStart.startingToss.firstName), 'All seats learn who the toss winner selected to start');
  await host.wait(m => isGame(m) && m.prompt?.inputKind === 'InputConfirmMulligan', 'host keep prompt');
  await player.wait(m => isGame(m) && m.prompt?.inputKind === 'InputConfirmMulligan', 'friend keep prompt before host keeps');
  check(true, 'All humans receive real Keep/Mulligan inputs together');
  const keepDeadline = Date.now() + 10000;
  while (Date.now() < keepDeadline && !player.messages.findLast(isGame).openingHandComplete) {
    step(player); // Deliberately leave the host's Keep unanswered.
    if (player.messages.at(-1)?.type === 'error') player.lastRevision = undefined;
    await pause(120);
  }
  check(player.messages.findLast(isGame).openingHandComplete && host.messages.findLast(isGame).prompt.inputKind === 'InputConfirmMulligan', 'The friend finishes Keep and leaves the opening screen while the host is still choosing');
  // Exercise the opening for both seats, so the checks below run against a game in progress.
  check(await drive([host, player, fourthPlayer], 1), 'Both seats can play through the opening decisions');

  // Another seat's decisions and stale identities are refused.
  const before = player.messages.findLast(isGame);
  player.send({type: 'shutdown', protocolVersion: 2, sessionId: before.sessionId, revision: before.revision, requestId: 'remote-shutdown'});
  check((await player.wait(m => m.requestId === 'remote-shutdown', 'remote shutdown rejection')).type === 'error', 'A joined player cannot shut down the host engine');
  const hostAsk = host.messages.findLast(isGame).asks?.[0];
  if (hostAsk) {
    player.send({type: 'answer', protocolVersion: 2, sessionId: before.sessionId, revision: before.revision, requestId: 'cross-seat', id: hostAsk.id, value: []});
    const reply = await player.wait(m => m.requestId === 'cross-seat', 'cross-seat reply');
    check(reply.type === 'error', 'One seat cannot answer another seat\'s decision');
  }
  player.send({type: 'action', action: 'ok', protocolVersion: 2, sessionId: 'wrong', revision: before.revision, requestId: 'wrong-session'});
  check((await player.wait(m => m.requestId === 'wrong-session', 'stale session reply')).code === 'stale_session', 'A wrong session is refused');

  // Disconnect and reconnect
  player.ws.close();
  await host.wait(m => isGame(m) && m.absentPlayers?.includes('Friend'), 'absent notice');
  check(true, 'The host is told a player has dropped');
  player = await open(onlineUrl);
  player.send({type: 'auth', token: start.token});
  const resumed = await player.wait(isGame, 'reconnected state');
  check(resumed.me === playerState.me && resumed.sessionId === playerState.sessionId, 'Reconnecting with the token restores the same seat');
  await host.wait(m => isGame(m) && m.absentPlayers?.length === 0, 'absent notice clearing');
  check(true, 'The absent notice clears on reconnect');
  const replacement = await open(onlineUrl);
  replacement.send({type: 'auth', token: start.token});
  await replacement.wait(isGame, 'replacement state');
  await pause(300);
  check(player.closed, 'A newer connection replaces the stale one');
  player = replacement;

  // Leaving hands the table back rather than freezing it.
  player.send({type: 'leave'});
  await pause(500);
  check(player.closed, 'Leaving closes the seat');
  const lost = await host.wait(m => isGame(m) && m.players.find(p => p.id === playerState.me).lost === true || (isGame(m) && m.absentPlayers?.length === 0 && m.revision > resumed.revision), 'seat release', 20000);
  check(lost, 'The table carries on after a player leaves');
  const startTurn = host.messages.findLast(isGame).game.turn;
  check(await drive([host, fourthPlayer], startTurn + 2), 'The host plays on through later turns, so the engine is not stuck on the empty seat');

  await call('match.stop', {owner, session: ready.session});
  check((await call('match.status', {owner})).state === 'stopped', 'Stopping the match ends it for the host');
  await pause(500);
  const rehosted = await call('lobby.host', {discover: false, config: {human, bots: [bot]}}).catch(() => null);
  check(rehosted?.hosting === true, 'The online port is free to host again afterwards');

  // Leaving while the engine waits on that player's own decision must not freeze the table.
  const priorityData = await call('lobby.deckText', {id: priorityDeck.id});
  const quitter = await open(onlineUrl);
  quitter.send(joinMessage('Quitter', {deckData: priorityData.deckData}));
  await quitter.wait(m => m.type === 'lobby', 'second session lobby');
  await call('lobby.config', {config: {human, bots: []}});
  quitter.send({type: 'ready', ready: true});
  await quitter.wait(m => m.type === 'lobby' && m.roster.some(p => p.kind === 'player' && p.ready), 'quitter ready');
  await call('lobby.ready', {ready: true});
  await call('match.start', {owner, id: priorityDeck.id, launchKey: 'online-check-launch-key-2', setup: {human, bots: []}});
  const secondStart = await quitter.wait(m => m.type === 'start', 'second session start');
  let secondReady;
  for (let tries = 0; tries < 400 && !secondReady; tries++) {
    const state = await call('match.status', {owner});
    if (state.state === 'failed') throw new Error(state.error);
    if (state.state === 'ready') secondReady = state; else await pause(300);
  }
  const isDuel = m => m.type === 'state' && !m.loading && m.players?.length === 2;
  const secondHost = await open(secondReady.url);
  let seat;
  for (let tries = 0; tries < 60 && !seat; tries++) { try { seat = await open(onlineUrl); } catch { await pause(250); } }
  seat.send({type: 'auth', token: secondStart.token});
  await seat.wait(isDuel, 'quitter state');
  check((await secondHost.wait(isDuel, 'two-player host state')).players.length === 2, 'A table of host and one player needs no bots');
  for (let tries = 0; tries < 150; tries++) {
    for (const peer of [secondHost, seat]) {
      const state = peer.messages.findLast(isDuel);
      if (state && state.prompt?.inputKind !== 'InputConfirmMulligan') step(peer);
    }
    if ([secondHost, seat].every(peer => peer.messages.findLast(isDuel)?.prompt?.inputKind === 'InputConfirmMulligan')) break;
    await pause(120);
  }
  await action(seat, 'cancel');
  await action(secondHost, 'ok');
  const replacementHand = await seat.wait(m => isDuel(m) && m.prompt?.inputKind === 'InputConfirmMulligan' && m.prompt.mulliganReturnCount === 1, 'replacement hand with one required bottom card');
  check(secondHost.messages.findLast(isDuel).openingHandComplete && !replacementHand.openingHandComplete, 'The host finishes Keep while the friend reviews a mulligan replacement');
  await action(seat, 'ok');
  const bottom = await seat.wait(m => isDuel(m) && m.prompt?.inputKind === 'InputLondonMulligan', 'real London bottom selection');
  check(!bottom.openingHandComplete && !bottom.prompt.okEnabled, 'A mulligan Keep does not finish until Forge receives the required bottom card');
  await action(seat, 'card', {id: bottom.players.find(p => p.id === bottom.me).zones.Hand[0].id});
  await seat.wait(m => isDuel(m) && m.prompt?.inputKind === 'InputLondonMulligan' && m.prompt.okEnabled, 'bottom choice accepted');
  await action(seat, 'ok');
  await seat.wait(m => isDuel(m) && m.openingHandComplete, 'final kept hand');
  check(await drive([secondHost, seat], 1), 'Both players finish real Keep and bottom-card decisions for the phase fixture');
  const controlledTurns = new Set();
  const phaseDeadline = Date.now() + 90000;
  let progressed = false;
  while (Date.now() < phaseDeadline && !progressed) {
    for (const peer of [secondHost, seat]) {
      const state = peer.messages.findLast(isDuel);
      if (state.game.turn >= 4) { progressed = true; break; }
      // Intentionally send NOTHING from the inactive seat, including the host.
      if (state.game.activePlayer === state.me) {
        controlledTurns.add(state.me);
        step(peer);
      }
      if (peer.messages.at(-1)?.type === 'error') peer.lastRevision = undefined;
    }
    await pause(120);
  }
  check(progressed && controlledTurns.size === 2, 'Both humans advance their own turns without any inactive-seat OK clicks');
  // The host answers everything; the quitter answers nothing until they are the one holding the game up.
  let holding = false;
  for (let tries = 0; tries < 300 && !holding; tries++) {
    step(secondHost);
    const held = seat.messages.findLast(isDuel);
    holding = held.asks?.length > 0 || (held.prompt?.inputKind && held.prompt.inputKind !== 'InputLockUI' && (held.prompt.okEnabled || held.prompt.cancelEnabled || held.prompt.entities?.length > 0));
    if (!holding) await pause(150);
  }
  check(holding, 'The engine is waiting on the quitting player');
  seat.send({type: 'leave'});
  const duelDone = await drive([secondHost], 3, 120000);
  check(duelDone, 'Leaving mid-decision frees the table');
  await call('match.stop', {owner, session: secondReady.session});
  check((await call('lobby.status')).hosting === false, 'No lobby remains after the session ends');

  // End a live match while a friend is still at Keep: the terminal notification
  // must arrive before socket teardown, including on Windows process stop.
  await call('lobby.host', {discover: false, config: {human, bots: []}});
  const waiting = await open(onlineUrl);
  waiting.send(joinMessage('Waiting friend', {deckData: priorityData.deckData}));
  await waiting.wait(m => m.type === 'lobby');
  waiting.send({type: 'ready', ready: true});
  await waiting.wait(m => m.type === 'lobby' && m.roster.some(p => p.ready));
  await call('lobby.ready', {ready: true});
  await call('match.start', {owner, id: priorityDeck.id, launchKey: 'online-check-lifecycle-3', setup: {human, bots: []}});
  const waitingStart = await waiting.wait(m => m.type === 'start');
  let live;
  for (let tries = 0; tries < 400 && !live; tries++) {
    const state = await call('match.status', {owner});
    if (state.state === 'failed') throw new Error(state.error);
    if (state.state === 'ready') live = state; else await pause(300);
  }
  const finalHost = await open(live.url);
  const finalFriend = await open(onlineUrl);
  finalFriend.send({type: 'auth', token: waitingStart.token});
  await finalFriend.wait(isDuel);
  for (let tries = 0; tries < 150; tries++) {
    for (const peer of [finalHost, finalFriend]) {
      const state = peer.messages.findLast(isDuel);
      if (state && state.prompt?.inputKind !== 'InputConfirmMulligan') step(peer);
    }
    if ([finalHost, finalFriend].every(peer => peer.messages.findLast(isDuel)?.prompt?.inputKind === 'InputConfirmMulligan')) break;
    await pause(120);
  }
  check(finalFriend.messages.findLast(isDuel)?.prompt?.inputKind === 'InputConfirmMulligan', 'Friend waits in its own opening hand before host stop');
  await call('match.stop', {owner, session: live.session});
  const ended = await finalFriend.wait(m => m.type === 'sessionEnded', 'terminal session-ended notice', 5000);
  check(ended.sessionId === finalFriend.messages.findLast(isDuel).sessionId && ended.message.includes('host'), 'Host End Game delivers a session-scoped terminal event to the friend');
  await call('lobby.host', {discover: false, config: {human, bots: []}});
  const cancelWaiting = await open(onlineUrl);
  cancelWaiting.send(joinMessage('Waiting friend'));
  await cancelWaiting.wait(m => m.type === 'lobby', 'cancelled lobby');
  await call('lobby.stop');
  check((await cancelWaiting.wait(m => m.type === 'closed', 'host cancellation')).message.includes('closed'), 'Cancelling hosting tells joined players');
  check((await call('lobby.status')).hosting === false, 'Cancelling hosting closes the lobby');
  await call('lobby.host', {discover: false, config: {human, bots: []}});
  library.ws.close();
  library = await open(`ws://127.0.0.1:${libraryPort}/ws`);
  for (let i = 0; i < 40 && (await call('lobby.status')).hosting; i++) await pause(100);
  check((await call('lobby.status')).hosting === false, 'Losing the host application closes its lobby');

  console.log(`\nonline-check: ${passed} checks passed`);
} catch (error) {
  console.error(`\nonline-check FAILED after ${passed} checks: ${error.message}\n--- service log tail ---\n${tail}\n${existsSync(join(fixture, 'service.log')) ? readFileSync(join(fixture, 'service.log'), 'utf8').slice(-6000) : ''}`);
  process.exitCode = 1;
} finally {
  for (const ws of sockets) { try { ws.close(); } catch {} }
  child.kill();
  await pause(1500);
  rmSync(fixture, {recursive: true, force: true});
  process.exit();
}
