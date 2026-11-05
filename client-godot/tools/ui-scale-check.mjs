import {spawn,spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdirSync,mkdtempSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {join,delimiter} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../..',import.meta.url));
const artifacts=join(root,'client-godot/artifacts');mkdirSync(artifacts,{recursive:true});
const fixture=mkdtempSync(join(artifacts,'ui-scale-fixture-'));
writeFileSync(join(fixture,'Scale.dck'),'[metadata]\nName=Scale test\n[Commander]\n1 Isamaru, Hound of Konda\n[Main]\n99 Plains\n');
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));
const port=probe.address().port;await new Promise(r=>probe.close(r));
const status=join(fixture,'startup.json');
// Windows' PATH Java launcher can spawn another JVM. Own the actual executable
// so service.kill() closes its pipes and stops the service, rather than only the shim.
const javaSettings=spawnSync('java',['-XshowSettings:properties','-version'],{encoding:'utf8',windowsHide:true});
const javaHome=javaSettings.stderr?.match(/^\s*java.home = (.+)$/m)?.[1].trim();
if(!javaHome)throw Error('Cannot locate Java');
const service=spawn(join(javaHome,'bin',process.platform==='win32'?'java.exe':'java'),['-Xmx4g','-cp',['bridge/target/classes','bridge/target/lib/*'].join(delimiter),
  'forgeui.bridge.LibraryMain','--assets',join(root,'forge/forge-gui'),'--library-root',fixture,
  '--port',String(port),'--startup-status',status,'--data-dir',fixture,'--parent-pid',String(process.pid)],{cwd:root,windowsHide:true});
let serviceLog='';for(const stream of [service.stdout,service.stderr])stream.on('data',b=>serviceLog+=b);
const nativeLog=join(fixture,'game.log');
const executable=process.env.FORGE_EXPORTED_EXE||process.env.FORGE_GODOT_PATH||join(root,process.platform==='darwin'?'.tools/godot/Godot.app/Contents/MacOS/Godot':'.tools/godot/Godot_v4.7.2-stable_win64.exe');
const app=spawn(executable,[...(process.env.FORGE_EXPORTED_EXE?[]:['--path',join(root,'client-godot')]),
  '--resolution','3200x2000','--log-file',nativeLog,'--','--ui-scale-check',...(process.argv.includes('--artwork-only')?['--artwork-only']:[]),`--library-url=ws://127.0.0.1:${port}/ws`,
  `--startup-status=${status}`,`--library-fixture=${fixture}`,`--ui-scale-capture=${artifacts}`],{cwd:root,windowsHide:true});
let output='',errors='';app.stdout.on('data',b=>{output+=b;process.stdout.write(b)});
app.stderr.on('data',b=>{errors+=b;process.stderr.write(b);if(/SCRIPT ERROR:|Parse Error:/.test(errors))app.kill()});
try {
  const code=await new Promise((ok,fail)=>{const timer=setTimeout(()=>{app.kill();fail(Error('UI scale check timed out'))},300000);
    app.on('error',fail);app.on('exit',c=>{clearTimeout(timer);ok(c)})});
  const transcript=output+errors+(existsSync(nativeLog)?readFileSync(nativeLog,'utf8'):'');
  if(code!==0||/SCRIPT ERROR:|ERROR:/.test(transcript)||!transcript.includes('PASS: 2x editor/game'))throw Error('UI scale verification failed');
  if(!output.includes('PASS: 2x editor/game'))process.stdout.write(readFileSync(nativeLog,'utf8'));
} finally {
  if(app.exitCode===null)app.kill();service.kill();
  writeFileSync(join(artifacts,'ui-scale-service.log'),existsSync(join(fixture,'service.log'))?readFileSync(join(fixture,'service.log'),'utf8'):serviceLog);
}
