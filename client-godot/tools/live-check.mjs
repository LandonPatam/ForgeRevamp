// A fresh Forge JVM + actual Godot table, with cleanup of only owned processes.
import {spawn, spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {existsSync, mkdirSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve, join, delimiter} from 'node:path';
const root = fileURLToPath(new URL('../..', import.meta.url));
const artifacts = join(root, 'client-godot/artifacts');
mkdirSync(artifacts, {recursive:true});
writeFileSync(join(artifacts, '.gdignore'), '');
const server = createServer();
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;
await new Promise(r => server.close(r));
const settings = spawnSync('java', ['-XshowSettings:properties', '-version'], {encoding:'utf8', windowsHide:true});
const home = settings.stderr.match(/^\s*java.home = (.+)$/m)?.[1].trim();
if (!home) throw Error('Cannot find JVM');
const wrongColor = process.argv.includes('--wrong-color');
const artifact = process.argv.includes('--artifact');
const takeback = process.argv.includes('--takeback');
const decisions = process.argv.includes('--decisions');
const manaChoices = process.argv.includes('--mana-choices');
const landReturn = process.argv.includes('--land-return');
const colorlessPayment = process.argv.includes('--colorless-payment');
const mulligan = process.argv.includes('--mulligan');
const interactions = process.argv.includes('--interactions');
const scenario = process.argv.find(arg => arg.startsWith('--scenario='))?.slice('--scenario='.length);
if (scenario && !existsSync(join(root, 'client-godot/tests/scenarios', scenario + '.state'))) throw Error('Unknown prepared scenario: add client-godot/tests/scenarios/' + scenario + '.state');
const logPrefix = scenario ? 'scenario-' + scenario : interactions ? 'interactions' : mulligan ? 'mulligan' : colorlessPayment ? 'colorless-payment' : landReturn ? 'land-return' : takeback ? 'takeback' : manaChoices ? 'mana-choices' : decisions ? 'decisions' : wrongColor ? 'wrong-color' : 'live';
const fixture = interactions ? 'engine-interactions.dck' : colorlessPayment ? 'engine-colorless-payment.dck' : landReturn ? 'engine-land-return.dck' : takeback ? 'engine-takeback.dck' : manaChoices ? 'engine-mana-choices.dck' : decisions ? 'engine-decisions.dck' : artifact ? 'engine-artifact.dck' : wrongColor ? 'engine-wrong-color.dck' : 'engine-commander.dck';
const bridge = spawn(join(home, 'bin', process.platform === 'win32' ? 'java.exe' : 'java'), ['-Xmx4g', '-cp', ['target/classes', 'target/lib/*'].join(delimiter), 'forgeui.bridge.BridgeMain', '--assets', '../forge/forge-gui', '--port', String(port), '--opponents', '2', '--deck-file', '../client-godot/tests/' + fixture, ...(scenario ? ['--test-state', '../client-godot/tests/scenarios/' + scenario + '.state'] : [])], {cwd:join(root, 'bridge'), windowsHide:true});
let bridgeLog = '', ready = false, godot;
for (const stream of [bridge.stdout, bridge.stderr]) stream.on('data', b => {bridgeLog += b; ready ||= bridgeLog.includes('Bridge ready:'); writeFileSync(join(artifacts, logPrefix + '-bridge.log'), bridgeLog);});
const pause = ms => new Promise(r => setTimeout(r, ms));
try {
  const deadline = Date.now() + 90000;
  while (!ready && Date.now() < deadline && bridge.exitCode === null) await pause(200);
  if (!ready) throw Error('Bridge startup failed');
  const rendered = process.argv.includes('--render');
  const args = ['--path', join(root, 'client-godot'), ...(rendered ? ['--resolution', '1600x1000', ...(process.platform === 'darwin' ? [] : ['--position', '-20000,-20000'])] : ['--headless']), '--', `--live=ws://127.0.0.1:${port}/ws`, '--live-check'];
  if (rendered) args.push(`--live-capture=${join(artifacts, scenario ? logPrefix + '-1600.png' : 'live-table-1600.png')}`);
  if (scenario) args.push('--expect-scenario=' + scenario);
  if (process.argv.includes('--token-online-images')) args.push('--token-online-images');
  if (wrongColor) args.push('--expect-wrong-color');
  if (artifact) args.push('--expect-artifact');
  if (takeback) args.push('--expect-takeback');
  if (decisions) args.push('--expect-decisions');
  if (manaChoices) args.push('--expect-mana-choices');
  if (landReturn) args.push('--expect-land-return');
  if (colorlessPayment) args.push('--expect-colorless-payment');
  if (mulligan) args.push('--expect-mulligan');
  if (interactions) args.push('--expect-interactions');
  godot = spawn(process.env.FORGE_GODOT_PATH || join(root, process.platform === 'darwin' ? '.tools/godot/Godot.app/Contents/MacOS/Godot' : '.tools/godot/Godot_v4.7.2-stable_win64.exe'), args, {cwd:root, windowsHide:true});
  let output = '', errors = '';
  godot.stdout.on('data', b => {output += b; process.stdout.write(b);});
  godot.stderr.on('data', b => {errors += b; process.stderr.write(b); if (/SCRIPT ERROR:|Parse Error:|Failed to load script/.test(errors)) godot.kill();});
  const code = await new Promise((ok, fail) => {
    const timer = setTimeout(() => fail(Error('Godot live check timed out')), 130000);
    godot.on('error', e => {clearTimeout(timer); fail(e);});
    godot.on('exit', c => {clearTimeout(timer); ok(c);});
  });
  writeFileSync(join(artifacts, logPrefix + '.stdout.log'), output);
  writeFileSync(join(artifacts, logPrefix + '.stderr.log'), errors);
  // A failed check() quits with code 1; unrelated engine "ERROR:" lines do not fail the run.
  if (code !== 0 || /SCRIPT ERROR:|Parse Error:/.test(errors) || !output.includes('PASS: Godot live integration')) throw Error('Godot live integration failed');
} catch (e) {
  console.error(e);
  console.error(bridgeLog.slice(-5000));
  process.exitCode = 1;
} finally {
  writeFileSync(join(artifacts, logPrefix + '-bridge.log'), bridgeLog);
  if (godot && godot.exitCode === null) godot.kill();
  bridge.kill();
}
