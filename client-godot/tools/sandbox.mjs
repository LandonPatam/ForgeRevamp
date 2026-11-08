// UI sandbox: open the real table on a prepared board without playing a game to get there.
//
//   node client-godot/tools/sandbox.mjs                 list boards
//   node client-godot/tools/sandbox.mjs <board>         real Forge engine on that board, playable window
//   node client-godot/tools/sandbox.mjs --mock          MockAdapter table (layout only, no rules)
//   node client-godot/tools/sandbox.mjs <board> --shot  save a screenshot and exit (artifacts/sandbox-<board>.png)
//
// Options: --opponents=1..3 (default 2), --deck=<tests/*.dck> (default engine-commander.dck),
//          --size=WxH (default 1600x1000), --no-watch.
// While running: saving a script/scene/shader relaunches the window on the SAME live board
// (the engine keeps its state); saving the board file restarts the board. Keys: r relaunch window,
// b restart board, q quit. Closing the window also quits. Boards live in client-godot/tests/sandbox/
// (UI playgrounds) and client-godot/tests/scenarios/ (the automated scenarios' boards).
import {spawn, spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync, watch} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {basename, join, delimiter, resolve} from 'node:path';

const root = fileURLToPath(new URL('../..', import.meta.url));
const client = join(root, 'client-godot');
const artifacts = join(client, 'artifacts');
const boardDirs = [join(client, 'tests/sandbox'), join(client, 'tests/scenarios')];
mkdirSync(artifacts, {recursive:true});
writeFileSync(join(artifacts, '.gdignore'), '');

const argv = process.argv.slice(2);
const option = name => argv.find(a => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const flag = name => argv.includes(`--${name}`);
const boardArg = argv.find(a => !a.startsWith('--'));
const mock = flag('mock');
const shot = flag('shot') || option('shot') !== undefined;
const watching = !flag('no-watch') && !shot;
const size = option('size') || '1600x1000';
const opponents = Math.max(1, Math.min(3, Number(option('opponents') || 2)));
const deck = option('deck') || 'engine-commander.dck';

function describe(file) {
  const first = readFileSync(file, 'utf8').split(/\r?\n/).find(l => l.startsWith('#'));
  return first ? first.replace(/^#\s*/, '') : '';
}

function listBoards() {
  for (const dir of boardDirs) {
    if (!existsSync(dir)) continue;
    console.log(`\n${dir.slice(root.length).replaceAll('\\', '/')}/`);
    for (const f of readdirSync(dir).filter(f => f.endsWith('.state')).sort()) {
      const name = f.slice(0, -6);
      console.log(`  ${name.padEnd(26)} ${describe(join(dir, f))}`);
    }
  }
  console.log('\nnode client-godot/tools/sandbox.mjs <board>   (or --mock for the mock table)');
}

function findBoard(name) {
  if (existsSync(name) && name.endsWith('.state')) return resolve(name);
  for (const dir of boardDirs) if (existsSync(join(dir, name + '.state'))) return join(dir, name + '.state');
  return null;
}

if (!boardArg && !mock) { listBoards(); process.exit(0); }
const boardFile = mock ? null : findBoard(boardArg);
if (!mock && !boardFile) { console.error(`No board named "${boardArg}".`); listBoards(); process.exit(1); }
if (!existsSync(join(client, 'tests', deck))) { console.error(`No fixture deck client-godot/tests/${deck}`); process.exit(1); }
const label = mock ? 'mock' : basename(boardFile, '.state');

const godotPath = process.env.FORGE_GODOT_PATH || join(root, process.platform === 'darwin'
  ? '.tools/godot/Godot.app/Contents/MacOS/Godot' : '.tools/godot/Godot_v4.7.2-stable_win64.exe');
let javaPath = null;
if (!mock) {
  const settings = spawnSync('java', ['-XshowSettings:properties', '-version'], {encoding:'utf8', windowsHide:true});
  const home = settings.stderr?.match(/^\s*java.home = (.+)$/m)?.[1].trim();
  if (!home) { console.error('Cannot find a Java 17 JVM on PATH.'); process.exit(1); }
  // Launch the real JVM, not a PATH shim, so killing it never orphans the engine.
  javaPath = join(home, 'bin', process.platform === 'win32' ? 'java.exe' : 'java');
  if (!existsSync(join(root, 'bridge/target/classes/forgeui/bridge/BridgeMain.class'))) {
    console.error('The bridge is not built. Run: node client-godot/tools/check.mjs bridge'); process.exit(1);
  }
}

const pause = ms => new Promise(r => setTimeout(r, ms));
const freePort = async () => {
  const s = createServer();
  await new Promise(r => s.listen(0, '127.0.0.1', r));
  const p = s.address().port;
  await new Promise(r => s.close(r));
  return p;
};
const say = msg => console.log(`[sandbox] ${msg}`);

let bridge = null, port = 0, godot = null, quitting = false, relaunching = false;

// Forge's state parser throws on blank lines; hand it a copy without them.
function preparedBoard() {
  const lines = readFileSync(boardFile, 'utf8').split(/\r?\n/).map(l => l.trimEnd()).filter(l => l.length);
  const copy = join(artifacts, 'sandbox-board.state');
  writeFileSync(copy, lines.join('\n') + '\n');
  return copy;
}

async function startBridge() {
  port = await freePort();
  const args = ['-Xmx4g', '-cp', ['target/classes', 'target/lib/*'].join(delimiter), 'forgeui.bridge.BridgeMain',
    '--assets', '../forge/forge-gui', '--port', String(port), '--opponents', String(opponents),
    '--deck-file', '../client-godot/tests/' + deck, '--test-state', preparedBoard()];
  const proc = spawn(javaPath, args, {cwd:join(root, 'bridge'), windowsHide:true});
  bridge = proc;
  let log = '', ready = false;
  const logFile = join(artifacts, 'sandbox-bridge.log');
  for (const stream of [proc.stdout, proc.stderr]) stream.on('data', b => {
    const text = b.toString();
    log += text;
    ready ||= log.includes('Bridge ready:');
    writeFileSync(logFile, log);
    // Surface what matters while editing boards: unknown cards and engine exceptions.
    for (const line of text.split(/\r?\n/)) {
      if (/Test state applied|Unknown (card|player)|Exception|Could not|not found/i.test(line)) say('engine: ' + line.trim());
    }
  });
  proc.on('exit', code => { if (bridge === proc && !quitting) { say(`engine exited (${code}); see ${logFile}`); shutdown(1); } });
  say(`starting Forge on board "${label}"...`);
  const deadline = Date.now() + 90000;
  while (!ready && Date.now() < deadline && proc.exitCode === null) await pause(200);
  if (!ready) { say(`engine failed to start; see ${logFile}`); shutdown(1); }
}

function stopBridge() {
  if (!bridge) return;
  const proc = bridge;
  bridge = null;
  if (proc.exitCode === null) proc.kill();
}

function launchGodot() {
  const [w, h] = size.split('x');
  const user = mock ? ['--mock'] : [`--live=ws://127.0.0.1:${port}/ws`, '--sandbox'];
  const shotFile = join(artifacts, `sandbox-${label}.png`);
  if (shot) user.push('--capture=' + shotFile);
  const args = ['--path', client, '--resolution', `${w}x${h}`,
    ...(shot && process.platform !== 'darwin' ? ['--position', '-20000,-20000'] : []), '--', ...user];
  const proc = spawn(godotPath, args, {cwd:root, windowsHide:shot});
  godot = proc;
  let out = '', tail = 0;
  const logFile = join(artifacts, 'sandbox-godot.log');
  const onData = b => {
    const text = b.toString();
    out += text;
    writeFileSync(logFile, out);
    // Echo script errors (and the stack lines that follow them) so a bad edit is obvious.
    for (const line of text.split(/\r?\n/)) {
      if (/SCRIPT ERROR|Parse Error|Failed to load script|Screenshot saved|Sandbox board ready/.test(line)) tail = 4;
      if (tail > 0 && line.trim()) { console.log('  ' + line.trim()); tail--; }
    }
  };
  proc.stdout.on('data', onData);
  proc.stderr.on('data', onData);
  proc.on('error', e => { say(`cannot start Godot (${godotPath}): ${e.message}`); shutdown(1); });
  proc.on('exit', code => {
    if (godot !== proc || relaunching) return;
    godot = null;
    if (shot) { shutdown(code === 0 && existsSync(shotFile) ? 0 : 1); return; }
    if (!quitting) { say('window closed'); shutdown(0); }
  });
  if (!shot) say(watching ? 'table open; edits relaunch it. Keys: r relaunch, b restart board, q quit' : 'table open');
}

async function relaunchWindow() {
  if (quitting) return;
  relaunching = true;
  if (godot && godot.exitCode === null) {
    const proc = godot;
    proc.kill();
    await new Promise(r => proc.exitCode !== null ? r() : proc.once('exit', r));
  }
  godot = null;
  relaunching = false;
  launchGodot();
}

async function restartBoard() {
  if (quitting) return;
  relaunching = true;
  if (godot && godot.exitCode === null) godot.kill();
  godot = null;
  if (!mock) { stopBridge(); await startBridge(); }
  relaunching = false;
  launchGodot();
}

function shutdown(code = 0) {
  if (quitting) return;
  quitting = true;
  if (godot && godot.exitCode === null) godot.kill();
  stopBridge();
  if (process.stdin.isTTY) process.stdin.setRawMode(false);
  process.exit(code);
}
process.on('SIGINT', () => shutdown(0));
process.on('SIGTERM', () => shutdown(0));
process.on('exit', () => { if (godot && godot.exitCode === null) godot.kill(); if (bridge && bridge.exitCode === null) bridge.kill(); });

if (!mock) await startBridge();
launchGodot();

if (watching) {
  let timer = null, pending = null;
  const queue = kind => {
    pending = pending === 'board' ? 'board' : kind;
    clearTimeout(timer);
    timer = setTimeout(() => {
      const what = pending;
      pending = null;
      if (what === 'board') { say('board changed; restarting it'); restartBoard(); }
      else { say('source changed; relaunching window on the same board'); relaunchWindow(); }
    }, 400);
  };
  for (const dir of ['scripts', 'scenes', 'assets/fonts', 'tests']) {
    const path = join(client, dir);
    if (!existsSync(path)) continue;
    watch(path, {recursive:true}, (_, name) => {
      if (!name || !/\.(gd|tscn|tres|gdshader)$/.test(name)) return;
      queue('window');
    });
  }
  if (boardFile) watch(boardFile, () => queue('board'));
}

if (process.stdin.isTTY && !shot) {
  process.stdin.setRawMode(true);
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', key => {
    if (key === 'q' || key === '\u0003') shutdown(0);
    else if (key === 'r') { say('relaunching window'); relaunchWindow(); }
    else if (key === 'b') { say(mock ? 'restarting mock table' : 'restarting board'); restartBoard(); }
  });
}
