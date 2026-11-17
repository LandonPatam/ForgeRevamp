#!/usr/bin/env node
// Turns an in-game bug report (F8, or saved automatically when the table got stuck) into a
// real-engine test board: tests/scenarios/<name>.state from the report's board.state, with the
// report's last decisions as comments, and prints what to put in the driver.
//   node client-godot/tools/report-to-scenario.mjs <report folder> <name>
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const [folder, name] = process.argv.slice(2);
if (!folder || !name || !/^[a-z0-9-]+$/.test(name)) {
  console.error('Usage: node client-godot/tools/report-to-scenario.mjs <report folder> <name (lowercase-with-dashes)>');
  process.exit(2);
}
const read = file => { try { return fs.readFileSync(path.join(folder, file), 'utf8'); } catch { return null; } };
const board = read('board.state');
if (!board) {
  console.error(`No board.state in ${folder}. Reports from a joined online seat have none; ask the host to press F8.`);
  process.exit(1);
}
const notes = (read('notes.txt') ?? '').trim().split(/\r?\n/)[0] ?? '';
let history = [];
try { history = JSON.parse(read('history.json') ?? '[]'); } catch { /* keep empty */ }
const last = history.at(-1) ?? {};
const oneLine = text => String(text ?? '').replace(/\s+/g, ' ').trim();
const asked = last.asks?.length ? `ask ${last.asks[0].kind} "${oneLine(last.asks[0].title || last.asks[0].message)}"` : `${last.inputKind ?? '?'} "${oneLine(last.message).slice(0, 140)}"`;

const scenarios = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'tests', 'scenarios');
const target = path.join(scenarios, `${name}.state`);
if (fs.existsSync(target)) { console.error(`${target} already exists`); process.exit(1); }
const header = [
  `# Reported: ${oneLine(notes).slice(0, 200)} At: ${asked}`,
  ...history.slice(-6).map(entry => `#   ${entry.phase ?? ''} ${entry.inputKind ?? ''} ${entry.asks?.length ? 'ask ' + entry.asks[0].kind : ''} ${oneLine(entry.message).slice(0, 100)}`.replace(/\s+/g, ' ')),
];
// Forge exports the board in the turn's current phase; the fixture starts there.
fs.writeFileSync(target, header.join('\n') + '\n' + board.replace(/\r\n/g, '\n').trimEnd() + '\n');
console.log(`Wrote ${path.relative(process.cwd(), target)}`);
console.log(`Last decision: ${asked}`);
console.log(`Next: add func ${name.replace(/-/g, '_')}() to tests/ScenarioIntegration.gd that reaches that decision`);
console.log(`(probe with dump("${name}")), confirm it fails, then fix. Open it by hand: node client-godot/tools/sandbox.mjs ${name}`);
if ((last.stack?.length ?? 0) > 0 || /trigger|beginning of|whenever|when /i.test(last.message ?? '') || last.asks?.length)
  console.log('Note: Forge exports the board, not the stack or triggers in flight. If the question came from a trigger or a spell, ' +
    'start the board one step earlier (edit activephase) or have the driver cast/trigger it again.');
