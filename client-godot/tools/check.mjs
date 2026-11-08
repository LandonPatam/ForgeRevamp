// Quiet, scoped test runner. Full output goes to client-godot/artifacts/check-logs/<step>.log;
// the console gets one line per step, plus the relevant lines when a step fails.
// Pipeline and which check to pick: docs/testing.md.
//
//   node client-godot/tools/check.mjs ui OutcomeScreen,PendingCast   headless tests/<Name>Checks.gd only
//   node client-godot/tools/check.mjs ui                             whole headless smoke suite
//   node client-godot/tools/check.mjs visual OutcomeScreen           rendered captures for those checks
//   node client-godot/tools/check.mjs scenario mind-stone [--render] real Forge + real table, prepared board
//   node client-godot/tools/check.mjs bridge                         build bridge + BridgeChecks (Java)
//   node client-godot/tools/check.mjs online | solo                  online lobby suite / solo phase stops
//   node client-godot/tools/check.mjs all                            full sweep, once, before a push
import {spawn, spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, readdirSync, statSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join, delimiter} from 'node:path';

const root = fileURLToPath(new URL('../..', import.meta.url));
const artifacts = join(root, 'client-godot/artifacts');
const logs = join(artifacts, 'check-logs');
mkdirSync(logs, {recursive: true});
writeFileSync(join(artifacts, '.gdignore'), '');
const [command = '', ...rest] = process.argv.slice(2);
const flags = rest.filter(arg => arg.startsWith('--'));
const names = rest.filter(arg => !arg.startsWith('--')).join(',');
const mac = process.platform === 'darwin';
const godot = process.env.FORGE_GODOT_PATH || join(root, mac ? '.tools/godot/Godot.app/Contents/MacOS/Godot' : '.tools/godot/Godot_v4.7.2-stable_win64_console.exe');
const FAILURE = /SCRIPT ERROR|Assertion failed|Parse Error|Failed to load script|^ERROR: (?!.*(?:not assigned to any set))/m;

function javaExe() {
  const settings = spawnSync('java', ['-XshowSettings:properties', '-version'], {encoding: 'utf8', windowsHide: true});
  const home = settings.stderr?.match(/^\s*java.home = (.+)$/m)?.[1].trim();
  if (!home) throw Error('Cannot locate Java');
  return join(home, 'bin', process.platform === 'win32' ? 'java.exe' : 'java');
}

/** Runs one step; resolves true/false and prints a single summary line (plus failure context). */
function step(label, exe, args, {cwd = root, timeout = 600000, done = null, shell = false} = {}) {
  const started = Date.now();
  const file = join(logs, label.replace(/[^\w.-]+/g, '_') + '.log');
  return new Promise(resolve => {
    let output = '';
    const child = spawn(exe, args, {cwd, windowsHide: true, shell});
    child.stdout.on('data', b => { output += b; });
    child.stderr.on('data', b => { output += b; });
    const timer = setTimeout(() => { output += '\nTIMED OUT\n'; child.kill(); }, timeout);
    child.on('error', error => { output += '\n' + error.message; });
    child.on('close', code => {
      clearTimeout(timer);
      writeFileSync(file, output);
      const seconds = Math.round((Date.now() - started) / 1000);
      const passes = (output.match(/^PASS\b.*$/gm) ?? []).length;
      const failed = code !== 0 || FAILURE.test(output) || output.includes('TIMED OUT') || (done && !done.test(output));
      console.log(`${failed ? 'FAIL' : 'PASS'} ${label} (${seconds}s${passes ? `, ${passes} PASS lines` : ''})${failed ? ' -> ' + file : ''}`);
      if (failed) {
        const lines = output.split(/\r?\n/);
        const hits = new Set();
        lines.forEach((line, i) => { if (FAILURE.test(line) || /assert|Exception|FAIL|TIMED OUT|not ok/i.test(line)) for (let k = i; k < Math.min(lines.length, i + 4); k++) hits.add(k); });
        const shown = [...hits].slice(0, 40).map(i => '  ' + lines[i].slice(0, 300));
        console.log((shown.length ? shown : lines.slice(-25).map(line => '  ' + line.slice(0, 300))).join('\n'));
      }
      resolve(!failed);
    });
  });
}

const headless = only => step(only ? `ui ${only}` : 'ui smoke', godot,
  ['--headless', '--path', join(root, 'client-godot'), '--quit-after', '100000', '--', '--smoke', ...(only ? [`--only=${only}`] : [])],
  {done: only ? /ONLY CHECKS DONE/ : /PASS: mock table smoke/});

async function visual(only) {
  const directory = join(artifacts, 'checks');
  mkdirSync(directory, {recursive: true});
  const since = Date.now();
  const ok = await step(only ? `visual ${only}` : 'visual all', godot,
    ['--path', join(root, 'client-godot'), '--resolution', '1600x1000', ...(mac ? [] : ['--position', '-20000,-20000']), '--', `--visual-checks=${directory}`, ...(only ? [`--only=${only}`] : [])],
    {done: only ? /ONLY CHECKS DONE/ : /PASS: rendered visual checks/});
  const fresh = readdirSync(directory).filter(file => file.endsWith('.png') && statSync(join(directory, file)).mtimeMs >= since);
  if (fresh.length) console.log(`  captures (${fresh.length}) in client-godot/artifacts/checks: ${fresh.slice(0, 12).join(', ')}${fresh.length > 12 ? ', …' : ''}`);
  return ok;
}

async function scenarios(list) {
  if (!list) {
    console.log('Scenarios: ' + readdirSync(join(root, 'client-godot/tests/scenarios')).filter(f => f.endsWith('.state')).map(f => f.slice(0, -6)).join(', '));
    return false;
  }
  let ok = true;
  // Each scenario owns one Forge JVM; run them one after another.
  for (const name of list.split(',')) ok = await step(`scenario ${name}`, process.execPath,
    [join(root, 'client-godot/tools/live-check.mjs'), `--scenario=${name}`, ...flags.filter(flag => flag === '--render')], {timeout: 240000}) && ok;
  return ok;
}

async function bridge() {
  const maven = join(root, '.tools/apache-maven-3.9.9/bin', process.platform === 'win32' ? 'mvn.cmd' : 'mvn');
  const built = await step('bridge build', existsSync(maven) ? maven : 'mvn', ['-q', '-o', '-f', join(root, 'bridge/pom.xml'), '-DskipTests', 'package'], {shell: process.platform === 'win32'});
  if (!built) return false;
  return step('bridge checks', javaExe(), ['-cp', ['target/test-classes', 'target/classes', 'target/lib/*'].join(delimiter), 'forgeui.bridge.BridgeChecks'], {cwd: join(root, 'bridge')});
}

const node = (label, script) => step(label, process.execPath, [join(root, script)], {timeout: 900000});

const commands = {
  ui: () => headless(names),
  visual: () => visual(names),
  scenario: () => scenarios(names),
  bridge,
  online: () => node('online', 'bridge/tools/online-check.mjs'),
  solo: () => node('solo phases', 'bridge/tools/solo-phase-check.mjs'),
  // Serial on purpose: online suites share Forge's online port and Godot runs compete for the GPU.
  all: async () => {
    let ok = true;
    for (const run of [() => headless(''), () => visual(''), bridge, commands.online, commands.solo]) ok = await run() && ok;
    return ok;
  },
};
if (!commands[command]) {
  console.log('Usage: node client-godot/tools/check.mjs <ui|visual|scenario|bridge|online|solo|all> [Names,...] [--render]\nSee docs/testing.md.');
  process.exit(2);
}
process.exitCode = (await commands[command]()) ? 0 : 1;
