// Isolated native collection/editor check. Never writes to the installed deck library.
import {spawn, spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdirSync, mkdtempSync, writeFileSync, readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const root = fileURLToPath(new URL('../..', import.meta.url));
const artifacts = join(root, 'client-godot/artifacts');
mkdirSync(artifacts, {recursive:true});
writeFileSync(join(artifacts, '.gdignore'), '');
const fixture = mkdtempSync(join(artifacts, 'library-fixture-'));
const cards = ["Sol Ring", "Command Tower", "Fathom Mage", "Hardened Scales", "Walking Ballista", "Contentious Plan", "Forgotten Ancient", "Cultivate", "Eternal Witness", "Heroic Intervention", "Swords to Plowshares", "Counterspell", "Doubling Season", "Dreadship Reef", "Seaside Citadel", "Elvish Mystic", "Forest", "Island", "Plains", "Swamp"];
const artKeys = Object.keys(JSON.parse(readFileSync(join(root,'client-godot/assets/cards/manifest.json'),'utf8')).byKey);
const printed = name => artKeys.find(key=>key.startsWith('c:'+name+'|'))?.slice(2) || name;
const decks = ["Atraxa", "Counter Culture", "Ancient Growth", "Wilderness", "Blink of an Eye", "Storage Wars", "Token Garden", "Witness", "Seaside"];
for (const [index,name] of decks.entries()) {
  writeFileSync(join(fixture, name + '.dck'), `[metadata]\nName=${name}\nComment=Preserve this test metadata\nTags=Integration\n[Commander]\n1 ${printed("Atraxa, Praetors' Voice")}\n[Main]\n${cards.map(c=>'1 '+printed(c)).join('\n')}\n${index + 50} ${printed('Forest')}\n`);
}
const server = createServer();
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const port = server.address().port;
await new Promise(r=>server.close(r));
const jvm = spawnSync('java',['-XshowSettings:properties','-version'],{encoding:'utf8',windowsHide:true});
const home = jvm.stderr.match(/^\s*java.home = (.+)$/m)?.[1].trim();
if (!home) throw Error('Cannot locate Java');
const bridge = spawn(join(home,'bin/java.exe'),['-Xmx4g','-cp','target/classes;target/lib/*','forgeui.bridge.LibraryMain','--assets','../forge/forge-gui','--port',String(port),'--library-root',fixture],{cwd:join(root,'bridge'),windowsHide:true});
let log = '', godot;
for (const stream of [bridge.stdout,bridge.stderr]) stream.on('data',b=>{log+=b;writeFileSync(join(artifacts,'library-bridge.log'),log)});
try {
  const deadline = Date.now()+90000;
  while (!log.includes('Library ready:') && Date.now()<deadline && bridge.exitCode===null) await new Promise(r=>setTimeout(r,200));
  if (!log.includes('Library ready:')) throw Error('Library failed to start');
  const render = process.argv.includes('--render');
  godot = spawn(process.env.FORGE_GODOT_PATH || join(root,'.tools/godot/Godot_v4.7.2-stable_win64.exe'),['--path',join(root,'client-godot'),'res://scenes/DeckCollection.tscn',...(render?['--resolution','1600x1000','--position','-20000,-20000']:['--headless']),'--',`--library-url=ws://127.0.0.1:${port}/ws`,'--library-check',...(process.argv.includes('--online-images')?['--library-online-images']:[]),`--library-fixture=${fixture}`,`--library-capture=${render?artifacts:''}`],{cwd:root,windowsHide:true});
  let output='',errors='';
  godot.stdout.on('data',b=>{output+=b;process.stdout.write(b)});
  godot.stderr.on('data',b=>{errors+=b;process.stderr.write(b);if(/SCRIPT ERROR:|Parse Error:|Failed to load script/.test(errors))godot.kill()});
  const code=await new Promise((ok,fail)=>{
    const timer=setTimeout(()=>fail(Error('Library UI test timed out')),140000);
    godot.on('error',e=>{clearTimeout(timer);fail(e)});
    godot.on('exit',c=>{clearTimeout(timer);ok(c)});
  });
  writeFileSync(join(artifacts,'library.stdout.log'),output);
  writeFileSync(join(artifacts,'library.stderr.log'),errors);
  if(code!==0 || /SCRIPT ERROR:|ERROR:/.test(errors) || !output.includes('PASS: Forge deck library integration'))throw Error('Library verification failed');
} catch(error) {console.error(error);console.error(log.slice(-2500));process.exitCode=1}
finally {if(godot && godot.exitCode===null)godot.kill();bridge.kill()}
