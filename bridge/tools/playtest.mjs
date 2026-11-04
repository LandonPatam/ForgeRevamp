// Plays real Commander games through the bridge's WebSocket protocol as the human seat.
// For each precon it launches an isolated bridge, auto-plays turns (lands, spells, targets,
// payment, attacks), compares what each card's rules text promises with what the game did,
// and writes a report. Only the JVMs started here are ever stopped.
//
//   node bridge/tools/playtest.mjs [--games 10] [--turns 6] [--timeout 420] [--seed 1]
//                                  [--decks "Abzan Armor,Ahoy Mateys"] [--parallel 1] [--trace] [--out DIR]
import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:net';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';

const bridgeRoot = fileURLToPath(new URL('../', import.meta.url));
const preconDir = join(bridgeRoot, '..', 'forge', 'forge-gui', 'res', 'quest', 'commanderprecons');
const argv = process.argv.slice(2);
const opt = (name, fallback) => { const i = argv.indexOf('--' + name); return i < 0 ? fallback : (argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : true); };
const options = {
  games: Number(opt('games', 10)), turns: Number(opt('turns', 6)), timeout: Number(opt('timeout', 420)) * 1000,
  seed: Number(opt('seed', 1)), decks: opt('decks', ''), parallel: Number(opt('parallel', 1)), trace: opt('trace', false) === true,
  out: opt('out', join(bridgeRoot, 'tools', 'playtest-reports')),
};
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
let rngState = options.seed >>> 0 || 1;
const random = () => { rngState = (rngState * 1664525 + 1013904223) >>> 0; return rngState / 4294967296; };
const pick = list => list[Math.floor(random() * list.length)];

// ------------------------------------------------------------------ JVM + socket

const javaSettings = spawnSync('java', ['-XshowSettings:properties', '-version'], { encoding: 'utf8', windowsHide: true });
const javaHome = javaSettings.stderr?.match(/^\s*java.home = (.+)$/m)?.[1].trim();
if (!javaHome) throw new Error('Could not locate the JVM home');
const javaExe = join(javaHome, 'bin', process.platform === 'win32' ? 'java.exe' : 'java');

async function freePort() {
  const probe = createServer();
  await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  return port;
}

async function launch(deckFile) {
  const port = await freePort();
  const child = spawn(javaExe, ['-Xmx3g', '-cp', 'target/classes;target/lib/*', 'forgeui.bridge.BridgeMain', '--assets', '../forge/forge-gui', '--port', String(port), '--deck-file', deckFile, '--opponents', '2'], { cwd: bridgeRoot, windowsHide: true });
  const host = { child, port, tail: '', ready: false, log: [] };
  for (const stream of [child.stdout, child.stderr]) stream.on('data', data => {
    const text = data.toString();
    host.ready ||= text.includes('Bridge ready:');
    host.tail = (host.tail + text).slice(-4000);
    // Keep each exception line with the first few stack frames that follow it.
    for (const line of text.split(/\r?\n/)) {
      if (/Exception|SEVERE|ERROR/.test(line) && !/not assigned to any set/.test(line)) { host.log.push(line.slice(0, 300)); host.frames = 4; }
      else if (host.frames > 0 && /^\s+at /.test(line)) { host.log[host.log.length - 1] += ' | ' + line.trim().slice(0, 120); host.frames--; }
      else host.frames = 0;
    }
  });
  const deadline = Date.now() + 120000;
  while (!host.ready) {
    if (child.exitCode !== null) throw new Error('Bridge exited during startup: ' + host.tail.slice(-400));
    if (Date.now() > deadline) throw new Error('Bridge startup timed out');
    await pause(300);
  }
  return host;
}

async function connect(host) {
  const ws = new WebSocket(`ws://127.0.0.1:${host.port}/ws`);
  const client = { ws, state: null, flashes: 0, errors: [], pending: new Map(), counter: 0, closed: false };
  ws.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.type === 'state' && !message.loading) {
      client.state = message;
      // A click can block inside Forge until a decision is answered, so its ack only arrives after
      // that answer. Release waiting senders as soon as an ask appears, like the UI does.
      if (message.asks?.length) for (const release of [...client.pending.values()]) release({ type: 'ack', code: 'pending-ask' });
    }
    else if (message.type === 'flash') client.flashes++;
    else if ((message.type === 'ack' || message.type === 'error') && client.pending.has(message.requestId)) client.pending.get(message.requestId)(message);
  };
  ws.onclose = () => { client.closed = true; };
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  client.send = (request) => new Promise(resolve => {
    const requestId = String(++client.counter);
    const timer = setTimeout(() => { client.pending.delete(requestId); resolve({ type: 'error', code: 'timeout', message: 'No reply from the bridge' }); }, 8000);
    client.pending.set(requestId, message => { clearTimeout(timer); client.pending.delete(requestId); resolve(message); });
    const state = client.state;
    ws.send(JSON.stringify({ protocolVersion: 2, sessionId: state.sessionId, revision: state.revision, requestId, ...request }));
  });
  client.hello = () => ws.send(JSON.stringify({ type: 'hello' }));
  return client;
}

// ------------------------------------------------------------------ state helpers

const me = s => s.players.find(p => p.id === s.me);
const zone = (s, name, player = me(s)) => player?.zones?.[name] ?? [];
const isLand = c => /\bLand\b/.test(c.typeLine ?? '');
const isCreature = c => /\bCreature\b/.test(c.typeLine ?? '');
const isPermanentSpell = c => /(Creature|Artifact|Enchantment|Planeswalker|Battle)/.test(c.typeLine ?? '');
const myTurn = s => s.game.activePlayer === s.me;
const snapshotOf = s => ({
  turn: s.game.turn, life: Object.fromEntries(s.players.map(p => [p.id, p.life])),
  hand: zone(s, 'Hand').map(c => c.id), battlefield: zone(s, 'Battlefield').map(c => c.id), graveyard: zone(s, 'Graveyard').map(c => c.id),
  exile: zone(s, 'Exile').map(c => c.id), handCount: me(s).handCount, libraryCount: me(s).libraryCount,
  tokens: zone(s, 'Battlefield').filter(c => c.token).length,
  handCounts: Object.fromEntries(s.players.map(p => [p.id, p.handCount])),
  libraryCounts: Object.fromEntries(s.players.map(p => [p.id, p.libraryCount])),
  graveyards: Object.fromEntries(s.players.map(p => [p.id, (p.zones.Graveyard ?? []).length])),
  allBattlefield: s.players.flatMap(p => (p.zones.Battlefield ?? []).map(c => c.id)),
});


const BASIC_COLORS = { Plains: 'W', Island: 'U', Swamp: 'B', Mountain: 'R', Forest: 'G' };
/** Colors an untapped permanent can add, from its text and basic land types ('*' = any color). */
function produces(card) {
  if (card.tapped) return [];
  const text = String(card.text ?? '').replace(/\\n/g, '\n');
  const colors = new Set();
  for (const [name, color] of Object.entries(BASIC_COLORS)) if (new RegExp(`\\b${name}\\b`).test(card.typeLine ?? '') && isLand(card)) colors.add(color);
  if (/\{T\}[^.\n]*: Add /i.test(text)) {
    for (const m of text.matchAll(/Add ([^.\n]*)/gi)) {
      if (/any (one )?color|any type/i.test(m[1])) colors.add('*');
      for (const sym of m[1].matchAll(/\{([WUBRGC])\}/g)) colors.add(sym[1]);
    }
  }
  return [...colors];
}
/** Greedy check that the untapped sources can pay a spell's mana cost. */
function canAfford(card, battlefield) {
  const symbols = String(card.manaCost ?? '').match(/\{[^}]+\}/g) ?? [];
  const pool = battlefield.map(produces).filter(list => list.length);
  let generic = 0;
  const colored = [];
  for (const symbol of symbols) {
    const inner = symbol.slice(1, -1);
    if (/^\d+$/.test(inner)) generic += Number(inner);
    else if (/^[WUBRGC]$/.test(inner)) colored.push(inner);
    else if (/X/.test(inner)) continue;
    else generic += 1; // hybrid/phyrexian: approximate as one mana of any kind
  }
  for (const color of colored) {
    const index = pool.findIndex(list => list.includes(color));
    const wild = pool.findIndex(list => list.includes('*'));
    const use = index >= 0 ? index : wild;
    if (use < 0) return false;
    pool.splice(use, 1);
  }
  return pool.length >= generic;
}

// ------------------------------------------------------------------ activated abilities

const cleanText = card => String(card.text ?? '').replace(/\\n/g, '\n').replace(/\([^)]*\)/g, ' ');
const COST_WORDS = /^(Sacrifice|Pay|Discard|Exile|Remove|Tap|Untap|Return|Reveal|Put|Mill|Exert|Collect)\b/i;

/** Activated abilities printed on a permanent: "cost: effect". Mana, loyalty and keyword lines are skipped. */
function abilitiesOf(card) {
  const found = [];
  for (const raw of cleanText(card).split(/\r?\n/)) {
    const line = raw.trim();
    const colon = line.indexOf(': ');
    if (colon < 1 || /^(When|Whenever|At the beginning)\b/i.test(line)) continue;
    const cost = line.slice(0, colon).trim(), effect = line.slice(colon + 2).trim();
    if (!/\{/.test(cost) && !COST_WORDS.test(cost)) continue;
    if (/^[+−-]\d|^0$/.test(cost) || /^Add\b/i.test(effect)) continue;
    const wantsPlayer = /\btarget (player|opponent)\b/i.test(effect) || /\bany target\b/i.test(effect);
    const beneficial = /\btarget player (draws?|gains?|untaps?|may draw)\b/i.test(effect);
    found.push({ line, cost, effect, wantsPlayer, prefer: wantsPlayer && beneficial ? 'self' : 'opponent', snippet: effect.slice(0, 24).toLowerCase() });
  }
  return found;
}

/** Can this permanent pay the ability's cost right now? Non-mana costs other than "{T}" and "Pay N life" are skipped. */
function abilityReady(card, ability, battlefield) {
  const needsTap = /\{T\}/.test(ability.cost);
  if (needsTap && (card.tapped || (isCreature(card) && card.sick))) return false;
  const rest = ability.cost.replace(/\{[^}]+\}/g, '').replace(/Pay \d+ life/gi, '').replace(/[,\s]/g, '');
  if (rest) return false;
  const symbols = (ability.cost.match(/\{[^}]+\}/g) ?? []).filter(sym => !/^\{[TQ]\}$/.test(sym));
  const sources = battlefield.filter(c => !(needsTap && c.id === card.id));
  return canAfford({ manaCost: symbols.join('') }, sources);
}

/** Judge an activated ability: did it ask for a target when its text names one, and did the effect land? */
function judgeAbility(play, before, after, state) {
  const verified = [], problems = [], unverified = [];
  const ability = play.ability, text = ability.effect;
  if (!play.activated) return { skipped: true, verified, problems, unverified };
  const target = play.chosenPlayer;
  const sawTarget = play.prompts.some(p => /Target|SelectEntities|SelectCards/.test(p.kind) || p.kind === 'ask:choose' || /target/i.test(p.message ?? ''));
  if (ability.wantsPlayer) {
    if (target == null) {
      if (sawTarget) verified.push('a target decision was offered');
      else problems.push(`Ability "${ability.line.slice(0, 90)}" names a target player but no target decision was offered`);
    } else verified.push(`a player target was chosen (${state.players.find(p => p.id === target)?.name})`);
  }
  if (/\{T\}/.test(ability.cost)) {
    const now = zone(state, 'Battlefield').find(c => c.id === play.card.id);
    if (now && !now.tapped && !/untap/i.test(text)) problems.push('The ability has a {T} cost but the permanent is untapped afterwards');
    else if (now) verified.push('{T} cost was paid');
  }
  const who = target ?? state.me;
  const count = word => asNumber(word);
  let m;
  if ((m = text.match(/target (?:player|opponent) draws? (a|an|one|two|three|\d+) cards?/i)) && target != null) {
    const delta = after.handCounts[target] - before.handCounts[target];
    if (delta >= count(m[1])) verified.push(`target drew ${count(m[1])}`); else problems.push(`Text says target draws ${count(m[1])} but their hand changed by ${delta}`);
  } else if ((m = text.match(/target player gains? (\d+) life/i)) && target != null) {
    const delta = after.life[target] - before.life[target];
    if (delta >= Number(m[1])) verified.push(`target gained ${m[1]} life`); else problems.push(`Text says target gains ${m[1]} life but life changed by ${delta}`);
  } else if ((m = text.match(/target (?:player|opponent) loses (\d+) life/i)) && target != null) {
    const delta = before.life[target] - after.life[target];
    if (delta >= Number(m[1])) verified.push(`target lost ${m[1]} life`); else problems.push(`Text says target loses ${m[1]} life but life changed by ${-delta}`);
  } else if ((m = text.match(/deals? (\d+) damage to (?:target (?:player|opponent)|any target)/i)) && target != null) {
    const delta = before.life[target] - after.life[target];
    if (delta >= Number(m[1])) verified.push(`dealt ${m[1]} damage to the chosen player`); else problems.push(`Text says ${m[1]} damage to the target but their life changed by ${-delta} (prevention or lifelink may explain this)`);
  } else if ((m = text.match(/target (?:player|opponent) mills? (a|an|one|two|three|four|five|\d+) cards?/i)) && target != null) {
    const delta = before.libraryCounts[target] - after.libraryCounts[target];
    if (delta >= count(m[1])) verified.push(`target milled ${count(m[1])}`); else problems.push(`Text says mill ${count(m[1])} but their library changed by ${-delta}`);
  } else if ((m = text.match(/target (?:player|opponent) discards? (a|an|one|two|three|\d+) cards?/i)) && target != null) {
    if (before.handCounts[target] === 0) unverified.push('target had no cards to discard');
    else if (before.handCounts[target] - after.handCounts[target] >= Math.min(count(m[1]), before.handCounts[target])) verified.push('target discarded');
    else problems.push(`Text says target discards ${count(m[1])} but their hand changed by ${after.handCounts[target] - before.handCounts[target]}`);
  } else if (/exile all cards from target player's graveyard/i.test(text) && target != null) {
    if ((after.graveyards[target] ?? 0) === 0) verified.push("exiled the target player's graveyard"); else problems.push("Target player's graveyard was not emptied");
  }
  if (!verified.length && !problems.length) unverified.push('no automatic check covers this ability');
  return { verified, problems, unverified, whoTargeted: who };
}

// ------------------------------------------------------------------ card checks

const WORD_NUMBERS = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7 };
const asNumber = word => /^\d+$/.test(word) ? Number(word) : WORD_NUMBERS[word.toLowerCase()];

/** Findings for one card play; `verified` lists patterns confirmed, `unverified` those no check covers. */
function judge(play, before, after, finalState) {
  if (play.kind === 'ability') return judgeAbility(play, before, after, finalState);
  const verified = [], problems = [], unverified = [];
  const card = play.card;
  // Only text this play actually triggers: an instant/sorcery's whole effect, or a permanent's
  // "When ... enters" lines. Activated abilities and static effects are not exercised by casting.
  const fullText = String(card.text ?? '').replace(/\\n/g, '\n').replace(/\([^)]*\)/g, ' ');
  const lines = fullText.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
  const spellLike = /(Instant|Sorcery)/.test(card.typeLine ?? '');
  const effectLines = spellLike ? lines.filter(l => !/^(Flashback|Cycling|Kicker|Entwine|Buyback|Escape|Overload|Casualty|Cleave)\b/i.test(l)) : lines.filter(l => /^(When|Whenever)\b.*\benters\b/i.test(l));
  const text = effectLines.join('\n');
  const sentences = text.split(/\n|(?<=\.)\s/).filter(Boolean);
  const entersTappedText = fullText;
  const stillInHand = after.hand.includes(card.id);
  if (play.kind === 'land') {
    const bounces = /return (a|an|one) [^.]*land[^.]* to (its|their) owner's hand/i.test(entersTappedText);
    if (!after.battlefield.includes(card.id) && bounces) verified.push('bounce land returned itself or another land as its text says');
    else if (!after.battlefield.includes(card.id)) problems.push('Land play was dispatched but the land never reached the battlefield');
    else verified.push('land entered the battlefield');
    if (/enters (the battlefield )?tapped/i.test(entersTappedText) && !/unless|if you control|you may (pay|reveal)|if you have|if you don't|as .* enters/i.test(entersTappedText)) {
      const land = zone(finalState, 'Battlefield').find(c => c.id === card.id);
      if (land && !play.sawUntapAtEntry) {
        if (land.tapped || play.tappedAtEntry) verified.push('enters tapped'); else problems.push('Text says it enters tapped but it was untapped on arrival');
      }
    }
  } else {
    if (stillInHand && !play.cast) return { skipped: true, verified, problems, unverified };
    if (play.cast) {
      if (isPermanentSpell(card) && !after.battlefield.includes(card.id) && !after.graveyard.includes(card.id) && !after.exile.includes(card.id) && !play.countered) {
        problems.push('Permanent spell resolved but is in no zone we can see (not battlefield/graveyard/exile)');
      } else if (!isPermanentSpell(card) && (after.graveyard.includes(card.id) || after.exile.includes(card.id))) verified.push('spell finished in graveyard/exile');
      else if (isPermanentSpell(card) && after.battlefield.includes(card.id)) verified.push('permanent entered the battlefield');
    }
  }
  const claimsTarget = sentences.some(s => /\btarget\b/i.test(s) && !/^Enchant\b/i.test(s) && !/^Equip\b/i.test(s));
  const sawTargetStep = play.prompts.some(p => /Target|SelectEntities|SelectCards/.test(p.kind) || /target/i.test(p.message ?? '') || p.kind === 'ask:choose');
  if (claimsTarget && (play.cast || play.kind === 'land')) {
    if (sawTargetStep) verified.push('a target decision was offered');
    else if (play.kind === 'land' || play.cast) problems.push('Rules text names a target but no target decision was ever offered' + (play.noLegalTarget ? ' (engine reported none legal)' : ''));
  }
  const draw = text.match(/\bdraw (a|an|one|two|three|four|five|\d+) cards?\b/i);
  if (draw && play.cast && !/\b(then|put|return|exile) /i.test(text) && !/target (player|opponent)/i.test(text) && !/each (opponent|player)/i.test(text) && !/discard|if |whenever|unless|may /i.test(text)) {
    const wanted = asNumber(draw[1]);
    const delta = after.handCount - before.handCount + (stillInHand ? 0 : 1);
    if (wanted && delta >= wanted) verified.push(`drew ${wanted}`); else if (wanted) problems.push(`Text says draw ${wanted} but hand grew by ${delta}`);
  }
  const gain = text.match(/\byou gain (\d+) life\b/i);
  if (gain && play.cast && !/whenever|if |unless|for each|equal to|may /i.test(text) && play.lifeStable) {
    const delta = after.life[finalState.me] - before.life[finalState.me];
    if (delta >= Number(gain[1])) verified.push(`gained ${gain[1]} life`); else problems.push(`Text says gain ${gain[1]} life but life changed by ${delta}`);
  }
  const token = text.match(/\bcreate (a|an|one|two|three|four|\d+) [^.]*?token/i);
  if (token && play.cast && !/whenever|if |unless|may |at the beginning/i.test(text)) {
    const wanted = asNumber(token[1]);
    if (wanted && after.tokens - before.tokens >= wanted) verified.push(`created ${wanted} token(s)`); else if (wanted) problems.push(`Text says create ${wanted} token(s) but token count changed by ${after.tokens - before.tokens}`);
  }
  if (/exile all cards from target player's graveyard/i.test(text) && play.chosenPlayer != null) {
    if ((after.graveyards[play.chosenPlayer] ?? 0) === 0) verified.push("exiled the target player's graveyard"); else problems.push("Target player's graveyard was not emptied");
  }
  if (!verified.length && !problems.length) unverified.push('no automatic check covers this text');
  return { verified, problems, unverified };
}

// ------------------------------------------------------------------ one game

async function playGame(deckFile, index) {
  const deckName = deckFile.split(/[\\/]/).pop().replace(/\.dck$/, '');
  const report = { deck: deckName, startedAt: new Date().toISOString(), turnsPlayed: 0, plays: [], findings: [], prompts: {}, errors: {}, outcome: 'unfinished', steps: 0 };
  const note = (severity, message, extra = {}) => { report.findings.push({ ...extra, severity, message, turn: client?.state?.game?.turn ?? 0 }); if (options.trace) console.log(`   [${severity}] ${message}`); };
  let host, client;
  const trace = (...parts) => { if (options.trace) console.log(`   ${deckName.slice(0, 18)}:`, ...parts); };
  try {
    host = await launch(deckFile);
    client = await connect(host);
    const startedAt = Date.now();
    const deadline = startedAt + options.timeout;
    let sameRevisionSince = Date.now(), lastRevision = -1, lastPromptKey = '';
    let paymentSteps = 0;
    const landsAtTurnStart = new Map();
    const activationsThisTurn = new Map();
    let landTurn = -1, active = null, castTries = new Map(), attackedTurn = -1, stuckPings = 0;
    const turnsSeen = new Set();
    const bumpPrompt = kind => { report.prompts[kind] = (report.prompts[kind] ?? 0) + 1; };

    let actedRevision = -2, actedAt = 0;
    const act = async (request, why) => {
      actedRevision = client.state?.revision ?? -2;
      actedAt = Date.now();
      const response = await client.send(request);
      report.steps++;
      trace('→', request.action ?? request.type, request.id ?? '', why ?? '', response.type === 'error' ? `ERR ${response.code}` : '');
      if (response.type === 'error') {
        if (response.code === 'timeout') note('warn', `The bridge did not answer ${request.action ?? request.type} (${why ?? ''}) within 8s`, { request: { action: request.action, id: request.id } });
        if (!['stale_state', 'stale_session', 'timeout'].includes(response.code)) {
          const key = `${response.code}: ${String(response.message).slice(0, 80)}`;
          report.errors[key] = (report.errors[key] ?? 0) + 1;
          if (report.errors[key] === 1) note('warn', `Bridge rejected an action (${key})`, { request: { action: request.action, id: request.id }, why });
        }
        client.hello();
      }
      return response;
    };

    const finishPlay = (state) => {
      if (!active) return;
      if (state.stack.some(item => item.card?.id === active.card.id || item.sourceId === active.card.id)) return; // still unresolved
      const after = snapshotOf(state);
      const verdict = judge(active, active.before, after, state);
      if (!verdict.skipped) {
        report.plays.push({ turn: active.turn, card: active.card.name, kind: active.kind, ability: active.ability?.line, text: String(active.card.text ?? '').slice(0, 300), prompts: active.prompts.map(p => p.kind + (p.title ? `: ${p.title}` : '')).slice(0, 12), ...verdict });
        for (const problem of verdict.problems) note('bug', `${active.card.name}: ${problem}`, { card: active.card.name, text: String(active.card.text ?? '').slice(0, 200) });
      }
      active = null;
    };

    while (Date.now() < deadline) {
      if (host.child.exitCode !== null) { note('bug', 'The bridge process exited during the game'); report.outcome = 'crashed'; break; }
      if (client.closed) { note('bug', 'The WebSocket closed unexpectedly'); report.outcome = 'disconnected'; break; }
      const s = client.state;
      if (!s) { await pause(100); continue; }
      // After acting, wait (briefly) for the bridge to publish a newer snapshot before deciding again.
      if (s.revision === actedRevision && Date.now() - actedAt < 2500) { if (Date.now() - actedAt > 400) client.hello(); await pause(30); continue; }
      if (s.revision !== lastRevision) { lastRevision = s.revision; sameRevisionSince = Date.now(); stuckPings = 0; }
      if (s.game.gameOver) { report.outcome = `game over (${s.game.winner || 'no winner'})`; break; }
      const mine = me(s);
      if (mine.lost) { report.outcome = 'local player lost'; break; }
      if (s.game.turn > 0) turnsSeen.add(s.game.turn);
      report.turnsPlayed = Math.ceil(s.game.turn / s.players.length);
      if (s.game.turn >= options.turns * s.players.length && myTurn(s) === false) { report.outcome = `stopped after ${options.turns} rounds`; break; }

      const prompt = s.prompt;
      const kind = prompt.inputKind ?? '';
      if (!/^InputPay/.test(kind) && kind) paymentSteps = 0;
      const promptKey = `${kind}|${prompt.message}|${s.asks.map(a => a.id).join(',')}|${s.stack.length}|${s.game.phaseKey}`;
      if (promptKey !== lastPromptKey) { lastPromptKey = promptKey; sameRevisionSince = Date.now(); }
      if (Date.now() - sameRevisionSince > 25000) {
        stuckPings++;
        note('bug', `The game made no progress for 25s at ${kind || 'no input'} / ${s.game.phase} (${String(prompt.message).replace(/<[^>]+>/g, '').slice(0, 120)})`, { asks: s.asks.map(a => `${a.kind}:${a.title || a.message || ''}`.slice(0, 120)) });
        sameRevisionSince = Date.now();
        if (stuckPings >= 3) { report.outcome = 'stuck'; break; }
        client.hello();
        await pause(500);
        continue;
      }

      if (active?.kind === 'ability' && !active.activated && s.stack.some(item => item.card?.id === active.card.id || item.sourceId === active.card.id)) active.activated = true;

      // ---------------- decisions the engine put to us as asks
      if (s.asks.length) {
        const ask = s.asks[0];
        bumpPrompt('ask:' + ask.kind);
        active?.prompts.push({ kind: 'ask:' + ask.kind, title: ask.title, message: ask.message });
        let value;
        if (ask.kind === 'message') value = true;
        else if (ask.kind === 'input') value = ask.default != null ? String(ask.default) : '0';
        else if (ask.kind === 'distribute') {
          const amounts = ask.options.map(() => 0); const total = ask.total ?? 1; amounts[0] = total; value = amounts;
        } else {
          const min = ask.min ?? 1, max = ask.max ?? min;
          const count = Math.min(ask.options.length, Math.max(min, Math.min(max, 1)));
          const indices = ask.options.map((_, i) => i).filter(i => !ask.options[i].disabled);
          value = (indices.length >= count ? indices : ask.options.map((_, i) => i)).slice(0, count);
          if (min === 0 && random() < 0.5) value = [];
          // Choosing among a card's abilities: take the one we meant to activate.
          if (active?.kind === 'ability' && !active.activated && ask.options.length > 1) {
            const wanted = ask.options.findIndex(o => String(o.label ?? '').toLowerCase().includes(active.ability.snippet));
            if (wanted >= 0) value = [wanted];
            else note('info', `Could not find "${active.ability.snippet}" among ${active.card.name}'s abilities; took the first`, { options: ask.options.map(o => String(o.label).slice(0, 60)) });
          }
          // A land or spell with alternatives (play vs cycle, cast vs flashback): take the plain play/cast.
          if ((active?.kind === 'land' || active?.kind === 'spell') && ask.options.length > 1 && /ability/i.test(String(ask.title ?? ''))) {
            const plain = ask.options.findIndex(o => /^(play|cast)\b|\bplay land\b|\bcast\b/i.test(String(o.label ?? '')) && !/cycl|flashback|foretell|channel|plot|adventure/i.test(String(o.label ?? '')));
            if (plain >= 0) value = [plain];
          }
          // A player choice (rather than a card): prefer who the ability's text implies.
          if (active?.ability?.wantsPlayer && ask.options.some(o => o.player != null || /^(player|opponent)/i.test(String(o.label ?? '')))) {
            const players = ask.options.map((o, i) => ({ o, i })).filter(({ o }) => o.player != null || /^(player|opponent)/i.test(String(o.label ?? '')));
            if (players.length) value = [players[0].i];
          }
        }
        trace('ask', ask.kind, String(ask.title || ask.message || '').slice(0, 80), '→', JSON.stringify(value).slice(0, 40));
        const response = await act({ type: 'answer', id: ask.id, value }, `ask ${ask.kind}`);
        if (response.type === 'error' && response.code === 'invalid_action') note('bug', `An ask answer was rejected: ${response.message}`, { ask: ask.kind, title: ask.title });
        await pause(40);
        continue;
      }
      if (s.pendingDraws?.length) { await act({ type: 'action', action: 'draw_ack', id: s.pendingDraws[0] }, 'draw'); continue; }
      if (s.undoPending) { await pause(80); continue; }
      if (!kind) { bumpPrompt('(none)'); await pause(60); continue; }
      bumpPrompt(kind);
      if (!/^InputPassPriority$|^InputAttack$|^InputBlock$|^InputConfirmMulligan$|^InputLockUI$/.test(kind)) active?.prompts.push({ kind, message: String(prompt.message).replace(/<[^>]+>/g, '').slice(0, 160) });

      // ---------------- engine inputs
      const hand = zone(s, 'Hand');
      const battlefield = zone(s, 'Battlefield');
      switch (kind) {
        case 'InputLockUI': await pause(60); break;
        case 'InputConfirmMulligan': await act({ type: 'action', action: 'ok' }, 'keep'); break;
        case 'InputLondonMulligan': {
          if (prompt.okEnabled) { await act({ type: 'action', action: 'ok' }, 'bottom done'); break; }
          const candidate = hand.find(c => !(prompt.chosen ?? []).includes(c.id) && !(prompt.chosen ?? []).includes('card:' + c.id));
          if (candidate) await act({ type: 'action', action: 'card', id: candidate.id }, 'bottom a card'); else await pause(100);
          break;
        }
        case 'InputAttack': {
          if (attackedTurn !== s.game.turn) {
            attackedTurn = s.game.turn;
            const defenders = s.players.filter(p => p.id !== s.me && !p.lost);
            const attackers = battlefield.filter(c => isCreature(c) && !c.tapped && !c.sick);
            for (const attacker of attackers.slice(0, 3)) {
              const defender = pick(defenders);
              const state = client.state;
              if (!defender || !state) continue;
              const response = await act({ type: 'action', action: 'attack', id: attacker.id, target: defender.id }, `attack with ${attacker.name}`);
              if (response.type === 'error' && !['stale_state', 'invalid_action'].includes(response.code)) note('bug', `Declaring an attacker failed: ${response.message}`);
              await pause(60);
            }
            report.attackSteps = (report.attackSteps ?? 0) + 1;
            if (attackers.length === 0) break;
          }
          if (client.state.prompt.okEnabled) await act({ type: 'action', action: 'ok' }, 'confirm attackers');
          break;
        }
        case 'InputBlock': await act({ type: 'action', action: 'ok' }, 'no blocks'); break;
        case 'InputPassPriority': {
          if (!prompt.okEnabled) { await pause(60); break; }
          const mainPhase = /MAIN/.test(s.game.phaseKey ?? '');
          if (myTurn(s) && mainPhase && s.stack.length === 0 && !s.pendingDraws?.length) {
            if (active && active.settleSteps === undefined) active.settleSteps = 0;
            if (active) { finishPlay(s); }
            if (!landsAtTurnStart.has(s.game.turn)) landsAtTurnStart.set(s.game.turn, battlefield.filter(isLand).length);
            const canLand = landTurn !== s.game.turn;
            const land = canLand ? hand.find(isLand) : null;
            if (land) {
              const failKey = 'land:' + s.game.turn;
              const attempt = { kind: 'land', card: land, turn: s.game.turn, before: snapshotOf(s), prompts: [], lifeStable: true };
              const response = await act({ type: 'action', action: 'card', id: land.id }, `play land ${land.name}`);
              if (response.type === 'ack') {
                landTurn = s.game.turn;
                active = attempt;
                await pause(120);
                active.tappedAtEntry = zone(client.state, 'Battlefield').find(c => c.id === land.id)?.tapped;
              } else if (response.code === 'invalid_action' || response.code === 'timeout') {
                // A rejected land play is only a finding if no land arrived this turn; otherwise the driver lost track.
                const landsNow = zone(client.state, 'Battlefield').filter(isLand).length;
                if (landsNow > (landsAtTurnStart.get(s.game.turn) ?? landsNow)) {
                  landTurn = s.game.turn;
                  note('info', `A land was already played on turn ${s.game.turn}; ignoring the extra attempt`);
                } else {
                  castTries.set(failKey, (castTries.get(failKey) ?? 0) + 1);
                  if (castTries.get(failKey) >= 3) {
                    landTurn = s.game.turn;
                    note('bug', `Forge rejected playing ${land.name} three times in a row on turn ${s.game.turn} though no land had been played`, { phase: s.game.phase, stack: s.stack.length, prompt: String(prompt.message).replace(/\n/g, ' | ').slice(0, 160), landsInPlay: landsNow, handLands: hand.filter(isLand).map(c => c.name), landDrops: s.players.find(p => p.id === s.me)?.landsPlayed ?? null });
                  } else { await pause(400); }
                }
              }
              continue;
            }
            const affordable = c => canAfford(c, battlefield);
            const spells = hand.filter(c => !isLand(c) && affordable(c) && (castTries.get(c.id + ':' + s.game.turn) ?? 0) < 1);
            if (spells.length) {
              const spell = pick(spells);
              castTries.set(spell.id + ':' + s.game.turn, 1);
              active = { kind: 'spell', card: spell, turn: s.game.turn, before: snapshotOf(s), prompts: [], cast: false, lifeStable: true, startedAt: report.steps };
              const flashesBefore = client.flashes;
              await act({ type: 'action', action: 'card', id: spell.id }, `cast ${spell.name}`);
              await pause(200);
              if (client.flashes > flashesBefore) { active.prompts.push({ kind: 'flash' }); }
              continue;
            }
            // Activated abilities of permanents already in play; player-targeting ones first.
            const ready = [];
            for (const card of battlefield) {
              for (const ability of abilitiesOf(card)) {
                if ((castTries.get(`ability:${card.id}:${ability.snippet}:${s.game.turn}`) ?? 0) >= 1) continue;
                if (abilityReady(card, ability, battlefield)) ready.push({ card, ability });
              }
            }
            const picks = ready.filter(r => r.ability.wantsPlayer);
            const choice = (picks.length ? picks : ready)[Math.floor(random() * (picks.length ? picks : ready).length)];
            if (choice && (activationsThisTurn.get(s.game.turn) ?? 0) < 3) {
              castTries.set(`ability:${choice.card.id}:${choice.ability.snippet}:${s.game.turn}`, 1);
              activationsThisTurn.set(s.game.turn, (activationsThisTurn.get(s.game.turn) ?? 0) + 1);
              active = { kind: 'ability', card: choice.card, ability: choice.ability, turn: s.game.turn, before: snapshotOf(s), prompts: [], activated: false, lifeStable: true };
              const flashesBefore = client.flashes;
              await act({ type: 'action', action: 'card', id: choice.card.id }, `activate ${choice.card.name}: ${choice.ability.line.slice(0, 50)}`);
              await pause(200);
              if (client.flashes > flashesBefore) active.prompts.push({ kind: 'flash' });
              continue;
            }
          }
          if (active && s.stack.length === 0 && (!myTurn(s) || !mainPhase)) finishPlay(s);
          await act({ type: 'action', action: 'ok' }, s.stack.length ? 'resolve stack' : 'pass');
          await pause(30);
          break;
        }
        case 'InputPayManaOfCostPayment': case 'InputPayMana': {
          if (active) { active.cast = true; if (active.kind === 'ability') active.activated = true; }
          paymentSteps++;
          if (paymentSteps > 10 && prompt.cancelEnabled) {
            note('info', `Payment for ${active?.card.name ?? 'a spell'} never completed after ${paymentSteps} steps; cancelled`, { message: String(prompt.message).replace(/<[^>]+>/g, '').slice(0, 140) });
            if (active) active.cast = false;
            paymentSteps = 0;
            await act({ type: 'action', action: 'cancel' }, 'payment stuck');
            break;
          }
          const suggested = battlefield.filter(c => (c.weakSelection ?? 0) > 0 && !c.tapped);
          const options = (prompt.selectable ?? []).length ? battlefield.filter(c => prompt.selectable.includes(c.id)) : suggested;
          if (prompt.okEnabled && !options.length) { await act({ type: 'action', action: 'ok' }, 'payment ok'); break; }
          const source = options[0] ?? suggested[0];
          if (source) await act({ type: 'action', action: 'card', id: source.id }, `tap ${source.name} for mana`);
          else if (prompt.okEnabled) await act({ type: 'action', action: 'ok' }, 'payment ok');
          else if (prompt.cancelEnabled) { note('info', `Could not pay for ${active?.card.name}; cancelled`); active && (active.cast = false); await act({ type: 'action', action: 'cancel' }, 'cannot pay'); }
          else await pause(100);
          break;
        }
        default: {
          // Targets and every other selection input.
          const chosen = prompt.chosen ?? [];
          const entities = prompt.entities ?? [];
          const need = prompt.selMin ?? 1;
          const candidates = [];
          for (const id of prompt.selectable ?? []) candidates.push({ type: 'card', id });
          for (const e of entities) if (e.kind === 'player' || e.type === 'player') candidates.push({ type: 'player', id: e.id });
          for (const c of s.players.flatMap(p => Object.values(p.zones).flat())) if ((c.weakSelection ?? 0) > 0 && !candidates.some(x => x.id === c.id)) candidates.push({ type: 'card', id: c.id });
          for (const target of prompt.targets ?? []) if (typeof target === 'number' && !candidates.some(x => x.id === target)) candidates.push({ type: 'card', id: target });
          const havePicked = chosen.length >= Math.max(1, need);
          if (prompt.okEnabled && (havePicked || need === 0)) { await act({ type: 'action', action: 'ok' }, 'confirm selection'); break; }
          let next = candidates.find(c => !chosen.some(x => String(x).endsWith(String(c.id))));
          if (active?.ability?.wantsPlayer) {
            // Pick the player the ability's text implies: yourself for beneficial effects, otherwise an opponent.
            const players = candidates.filter(c => c.type === 'player' && !chosen.some(x => String(x).endsWith(String(c.id))));
            const wanted = players.find(c => (c.id === s.me) === (active.ability.prefer === 'self')) ?? players[0];
            if (wanted) next = wanted;
          }
          if (next) {
            if (active?.kind === 'ability') active.activated = true;
            if (active && next.type === 'player') active.chosenPlayer = next.id;
            await act({ type: 'action', action: next.type === 'player' ? 'player' : 'card', id: next.id }, `choose ${next.type} ${next.id}`);
          } else if (prompt.okEnabled) await act({ type: 'action', action: 'ok' }, 'confirm (no candidates)');
          else if (prompt.cancelEnabled) { if (active) active.noLegalTarget = true; note('info', `No selectable candidates for ${kind}; cancelled (${active?.card.name ?? 'unknown source'})`); await act({ type: 'action', action: 'cancel' }, 'no candidates'); }
          else {
            if (Date.now() - sameRevisionSince > 4000) note('warn', `Unhandled input ${kind}: no OK/Cancel and no selectable candidates`, { message: String(prompt.message).slice(0, 120) });
            await pause(120);
          }
        }
      }
    }
    if (Date.now() >= deadline && report.outcome === 'unfinished') report.outcome = 'time limit';
    if (client.state) { finishPlay(client.state); report.final = { turn: client.state.game.turn, life: Object.fromEntries(client.state.players.map(p => [p.name, p.life])) }; }
    for (const line of host.log.slice(0, 20)) note('bug', 'Java log: ' + line);
  } catch (error) {
    note('bug', 'Test driver error: ' + (error?.stack ?? error));
    report.outcome = 'driver error';
  } finally {
    try { client?.ws.close(); } catch { /* already closed */ }
    host?.child.kill();
    await Promise.race([new Promise(resolve => host?.child.once('exit', resolve)), pause(3000)]);
    if (host && host.child.exitCode === null && host.child.signalCode === null) host.child.kill('SIGKILL');
  }
  report.seconds = Math.round((Date.now() - Date.parse(report.startedAt)) / 1000);
  return report;
}

// ------------------------------------------------------------------ run + report

const allDecks = fs.readdirSync(preconDir).filter(f => f.endsWith('.dck')).sort();
let chosen;
if (options.decks) {
  const wanted = String(options.decks).split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
  chosen = wanted.map(w => allDecks.find(d => d.toLowerCase().includes(w))).filter(Boolean);
} else {
  const pool = [...allDecks];
  chosen = [];
  while (chosen.length < Math.min(options.games, pool.length)) chosen.push(pool.splice(Math.floor(random() * pool.length), 1)[0]);
}
fs.mkdirSync(options.out, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
console.log(`Playing ${chosen.length} game(s) as the human seat (seed ${options.seed}, ${options.turns} rounds, ${options.timeout / 1000}s cap each)`);
const reports = [];
let cursor = 0;
await Promise.all(Array.from({ length: Math.max(1, options.parallel) }, async () => {
  while (cursor < chosen.length) {
    const index = cursor++;
    const report = await playGame(join(preconDir, chosen[index]), index);
    reports.push(report);
    const bugs = report.findings.filter(f => f.severity === 'bug').length;
    console.log(`[${index + 1}/${chosen.length}] ${report.deck}: ${report.outcome}; rounds ${report.turnsPlayed}, ${report.plays.length} card plays, ${bugs} bug finding(s), ${report.seconds}s`);
    fs.writeFileSync(join(options.out, `${stamp}.json`), JSON.stringify({ options, reports }, null, 1));
  }
}));

const lines = [`# Playtest report ${stamp}`, '', `${reports.length} game(s), seed ${options.seed}.`, ''];
for (const report of reports) {
  const bugs = report.findings.filter(f => f.severity === 'bug');
  const warns = report.findings.filter(f => f.severity === 'warn');
  lines.push(`## ${report.deck}`, `Outcome: **${report.outcome}**, ${report.turnsPlayed} rounds, ${report.plays.length} card plays, ${report.seconds}s.`, '');
  lines.push(`Prompts seen: ${Object.entries(report.prompts).map(([k, v]) => `${k}×${v}`).join(', ') || 'none'}`, '');
  if (bugs.length) { lines.push('**Bugs**'); for (const f of bugs) lines.push(`- (turn ${f.turn}) ${f.message}${f.text ? `\n  - text: ${f.text}` : ''}`); lines.push(''); }
  if (warns.length) { lines.push('Warnings'); for (const f of warns) lines.push(`- (turn ${f.turn}) ${f.message}`); lines.push(''); }
  const verified = report.plays.filter(p => p.verified.length && !p.problems.length);
  const unverified = report.plays.filter(p => !p.verified.length && !p.problems.length);
  lines.push(`Verified plays: ${verified.length}. Unverified (no automatic check): ${unverified.length}.`);
  for (const p of verified.slice(0, 12)) lines.push(`- ✔ ${p.card}: ${p.verified.join('; ')}`);
  for (const p of unverified.slice(0, 12)) lines.push(`- ? ${p.card} — ${String(p.text).replace(/\n/g, ' ').slice(0, 110)}`);
  lines.push('');
}
const markdown = join(options.out, `${stamp}.md`);
fs.writeFileSync(markdown, lines.join('\n'));
const totalBugs = reports.reduce((sum, r) => sum + r.findings.filter(f => f.severity === 'bug').length, 0);
console.log(`\nReport: ${markdown}\n${totalBugs} bug finding(s) across ${reports.length} game(s).`);
process.exitCode = totalBugs ? 1 : 0;
