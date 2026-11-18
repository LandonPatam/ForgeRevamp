#!/usr/bin/env node
// Card-shape sweep: edge cases cluster by how a card is scripted, not by its name. This scans
// Forge's card scripts, groups castable spells and "when this enters" cards by ability shape
// (any number of targets, "you may" targets, choose X or Y, library search, divided damage, ...),
// picks a few representatives per shape and writes a generated board for each:
// tests/scenarios/shape-<shape>-<n>.state (git-ignored). `check.mjs shapes` then plays each one
// through the real table (ScenarioIntegration.shape_probe) and fails if any question can't be
// answered on screen.
//   node client-godot/tools/shape-sweep.mjs [--per 3] [--only shape,shape] [--list]
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const cardsFolder = path.join(root, 'forge/forge-gui/res/cardsfolder');
const scenarios = path.join(root, 'client-godot/tests/scenarios');
const args = process.argv.slice(2);
const option = name => { const at = args.indexOf(name); return at >= 0 ? args[at + 1] : undefined; };
const per = Number(option('--per') ?? 3);
const only = option('--only')?.split(',');

// Each shape: a test on the effect text of the card's spell ability or its own enters trigger.
const SHAPES = {
  'any-number-targets': t => /TargetMin\$\s*0/.test(t) && /TargetMax\$\s*(X|[2-9]|\d\d)/.test(t),
  'several-targets': t => /TargetMin\$\s*[2-9]/.test(t),
  'optional-target-trigger': (t, c) => c.etb && /OptionalDecider\$\s*You/.test(c.trigger) && /ValidTgts\$/.test(t),
  'generic-choice': t => /\$\s*GenericChoice/.test(t),
  'charm': t => /\$\s*Charm/.test(t),
  'library-search': t => /\$\s*ChangeZone/.test(t) && /Origin\$\s*Library/.test(t) && /(Hidden\$\s*True|ChangeType\$)/.test(t),
  'dig': t => /\$\s*Dig\b/.test(t),
  'graveyard-target': t => /TgtZone\$\s*Graveyard/.test(t),
  'divided-damage': t => /DividedAsYouChoose/.test(t),
  'choose-color': t => /\$\s*ChooseColor/.test(t),
  'choose-type': t => /\$\s*ChooseType/.test(t),
  'choose-card': t => /\$\s*ChooseCard/.test(t),
  'choose-player': t => /\$\s*ChoosePlayer/.test(t),
  'sacrifice-choice': t => /\$\s*Sacrifice\b/.test(t) && /SacValid\$/.test(t),
  'discard-choice': t => /\$\s*Discard\b/.test(t) && /Mode\$\s*TgtChoose/.test(t),
  'counters': t => /\$\s*(PutCounter|MultiplyCounter|Proliferate|RemoveCounter)\b/.test(t),
  'scry-surveil': t => /\$\s*(Scry|Surveil)\b/.test(t),
  'vote': t => /\$\s*Vote\b/.test(t),
  'pump-all-or-destroy-all': t => /\$\s*(DestroyAll|ChangeZoneAll|PumpAll|DamageAll)\b/.test(t),
  'copy-or-clone': t => /\$\s*(Clone|CopyPermanent|CopySpellAbility)\b/.test(t),
  'x-spell': (t, c) => /X/.test(c.cost),
  'gain-control': t => /\$\s*GainControl\b/.test(t),
  'attach-aura': (t, c) => /Aura/.test(c.types),
  'modal-repeat': t => /CanRepeatModes\$/.test(t),
};

function* files(dir) {
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    if (entry.isDirectory()) { if (entry.name !== 'upcoming') yield* files(path.join(dir, entry.name)); }
    else if (entry.name.endsWith('.txt')) yield path.join(dir, entry.name);
  }
}

// One card script → its castable effect text, or null when it isn't a plain main-phase card.
function parse(file) {
  const text = fs.readFileSync(file, 'utf8');
  if (/^AlternateMode:/m.test(text) || /^ALTERNATE/m.test(text)) return null; // split/MDFC/adventure: later
  const field = name => text.match(new RegExp(`^${name}:(.*)$`, 'm'))?.[1]?.trim() ?? '';
  const name = field('Name'), types = field('Types'), cost = field('ManaCost');
  if (!name || !cost || cost === 'no cost' || /Land|Conspiracy|Scheme|Plane\b|Vanguard|Phenomenon|Attraction|Contraption|Dungeon/.test(types)) return null;
  if (/^(A-|Ac-)/.test(name) || /\{|\}|Un-|^R:\s*Mode\$ Draw/m.test(name)) return null; // Alchemy rebalanced and odd names
  const svars = Object.fromEntries([...text.matchAll(/^SVar:([^:]+):(.*)$/gm)].map(m => [m[1], m[2]]));
  // Follow Execute$ / SubAbility$ chains so a trigger's whole effect is tested.
  const expand = (line, seen = new Set()) => {
    let out = line;
    for (const ref of line.matchAll(/(?:Execute|SubAbility|Choices|Defined\$ Remembered)\$\s*([\w,]+)/g)) {
      for (const key of ref[1].split(',')) {
        if (svars[key] && !seen.has(key)) { seen.add(key); out += '\n' + expand(svars[key], seen); }
      }
    }
    return out;
  };
  const spell = [...text.matchAll(/^A:SP\$.*$/gm)].map(m => expand(m[0])).join('\n');
  const etbLine = [...text.matchAll(/^T:Mode\$\s*ChangesZone.*$/gm)].map(m => m[0])
    .find(line => /Destination\$\s*Battlefield/.test(line) && /ValidCard\$\s*Card\.Self\b/.test(line)) ?? '';
  const etb = etbLine ? expand(etbLine) : '';
  // Permanent spells (no SP$ line) still cast fine; their interesting part is the enters trigger.
  const permanent = /Creature|Artifact|Enchantment|Planeswalker|Battle/.test(types);
  if (!spell && !(permanent && etb) && !/Aura/.test(types)) return null;
  const mana = (cost.match(/\d+/g) ?? []).reduce((a, b) => a + Number(b), 0) + (cost.match(/[WUBRGC]/g) ?? []).length;
  if (mana > 8 || /\{?S\}?/.test(cost.replace(/\s/g, '')) && /\bS\b/.test(cost)) return null; // snow mana: later
  return {name, types, cost, mana, etb: !!etb, trigger: etbLine, effect: spell + '\n' + etb};
}

const cards = [];
for (const file of files(cardsFolder)) {
  const card = parse(file);
  if (card) cards.push(card);
}
const byShape = {};
for (const [shape, test] of Object.entries(SHAPES)) {
  if (only && !only.includes(shape)) continue;
  byShape[shape] = cards.filter(card => { try { return test(card.effect, card); } catch { return false; } });
}
if (args.includes('--list')) {
  for (const [shape, list] of Object.entries(byShape)) console.log(`${shape}: ${list.length} cards, e.g. ${list.slice(0, 5).map(c => c.name).join('; ')}`);
  process.exit(0);
}

// Deterministic, spread-out picks: cheap cards first, then evenly across the alphabet.
function pick(list, count) {
  const sorted = [...list].sort((a, b) => a.mana - b.mana || a.name.localeCompare(b.name));
  const cheap = sorted.filter(card => card.mana <= 6);
  const pool = cheap.length >= count ? cheap : sorted;
  if (pool.length <= count) return pool;
  const step = pool.length / count;
  return Array.from({length: count}, (_, i) => pool[Math.floor(i * step + step / 2)]);
}

// A busy table so most effects have something to act on: creatures with counters, artifacts,
// enchantments, a planeswalker, cards in graveyards, a library worth searching, and plenty of
// floating mana of every color that lasts all turn.
const library = 'Forest;Island;Swamp;Mountain;Plains;Grizzly Bears;Llanowar Elves;Sol Ring;Lightning Bolt;Counterspell;Wrath of God;Serra Angel;Forest;Island;Swamp;Mountain;Plains;Craw Wurm;Ornithopter;Divination';
const board = card => [
  `# Shape sweep: cast ${card.name}; the table must offer every decision it asks.`,
  'activeplayer=p0',
  'activephase=MAIN1',
  'turn=5',
  'removesummoningsickness=true',
  'p0life=40',
  `p0hand=${card.name}`,
  'p0persistentmana=W W W W U U U U B B B B R R R R G G G G C C C C',
  'p0battlefield=Grizzly Bears|Counters:P1P1=1;Llanowar Elves;Sol Ring;Glorious Anthem;Jace Beleren|Counters:LOYALTY=3;Forest;Island',
  'p0graveyard=Craw Wurm;Lightning Bolt;Swamp',
  `p0library=${library}`,
  'p1life=40',
  'p1battlefield=Serra Angel;Goblin Guide|Counters:P1P1=1;Ornithopter;Pacifism;Mountain',
  'p1graveyard=Grizzly Bears;Divination',
  `p1library=${library}`,
  'p2life=40',
  'p2battlefield=Craw Wurm;Plains',
  `p2library=${library}`,
].join('\n') + '\n';

for (const old of fs.readdirSync(scenarios).filter(f => /^shape-.*\.state$/.test(f))) fs.unlinkSync(path.join(scenarios, old));
const written = [];
for (const [shape, list] of Object.entries(byShape)) {
  pick(list, per).forEach((card, index) => {
    const name = `shape-${shape}-${index + 1}`;
    fs.writeFileSync(path.join(scenarios, name + '.state'), board(card));
    written.push(`${name}: ${card.name}`);
  });
}
console.log(`Scanned ${cards.length} castable cards; wrote ${written.length} boards:`);
for (const line of written) console.log('  ' + line);
console.log('Run them: node client-godot/tools/check.mjs shapes');
