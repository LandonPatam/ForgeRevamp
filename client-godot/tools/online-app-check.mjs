// Tests the exported Mac game and its bundled service through the real online application flow.
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdirSync,mkdtempSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {join,resolve,dirname,delimiter} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../..',import.meta.url));
const artifacts=join(root,'client-godot/artifacts');mkdirSync(artifacts,{recursive:true});
const fixture=mkdtempSync(join(artifacts,'online-app-fixture-'));
writeFileSync(join(fixture,'Scale.dck'),'[metadata]\nName=Scale test\n[Commander]\n1 Isamaru, Hound of Konda\n[Main]\n99 Plains\n');
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));
const port=probe.address().port;await new Promise(r=>probe.close(r));
const status=join(fixture,'startup.json');
const source=process.argv.includes('--source');
const executable=resolve(source?(process.env.FORGE_GODOT_PATH||join(root,'.tools/godot/Godot.app/Contents/MacOS/Godot')):(process.env.FORGE_EXPORTED_EXE||join(root,'dist/ForgeUI-mac-optimized/ForgeUI.app/Contents/MacOS/ForgeUI')));
const intel=process.argv.includes('--intel');
const peerIndex=process.argv.indexOf('--peer');
const peer=peerIndex<0?'':process.argv[peerIndex+1];
const resources=resolve(dirname(executable),'../Resources');
const bundledJava=join(resources,'runtime',intel?'x86_64':process.arch==='arm64'?'arm64':'x86_64','Contents/Home/bin/java');
const service=spawn(source?'java':bundledJava,['-Xmx4g','-cp',(source?[join(root,'bridge/target/classes'),join(root,'bridge/target/lib/*')]:[join(resources,'service/classes'),join(resources,'service/lib/*')]).join(delimiter),
  'forgeui.bridge.LibraryMain','--assets',source?join(root,'forge/forge-gui'):join(resources,'forge-gui'),'--library-root',fixture,
  '--port',String(port),'--startup-status',status,'--data-dir',fixture,'--parent-pid',String(process.pid)],{cwd:root});
let serviceLog='';for(const stream of [service.stdout,service.stderr])stream.on('data',b=>serviceLog+=b);
const nativeLog=join(fixture,'game.log');
console.log('Online application fixture:',fixture);
const app=spawn(intel?'/usr/bin/arch':executable,[...(intel?['-x86_64',executable]:[]),...(source?['--path',join(root,'client-godot')]:[]),
  '--resolution','1600x1000','--log-file',nativeLog,'--','--app-check','--app-online-check',`--library-url=ws://127.0.0.1:${port}/ws`,
  `--startup-status=${status}`,`--library-fixture=${fixture}`,`--online-report=${join(fixture,"live-status.json")}`,...(peer?[`--online-peer=${peer}`]:[])],{cwd:root});
let output='',errors='';app.stdout.on('data',b=>{output+=b;process.stdout.write(b)});
app.stderr.on('data',b=>{errors+=b;process.stderr.write(b);if(/SCRIPT ERROR:|Parse Error:/.test(errors))app.kill()});
try {
  const code=await new Promise((ok,fail)=>{const timer=setTimeout(()=>{app.kill();fail(Error('Online application check timed out'))},peer?700000:360000);
    app.on('error',fail);app.on('exit',c=>{clearTimeout(timer);ok(c)})});
  const transcript=output+errors+(existsSync(nativeLog)?readFileSync(nativeLog,'utf8'):'');
  if(code!==0||/SCRIPT ERROR:|ERROR:/.test(transcript)||!transcript.includes(peer?'PASS: live Mac-to-Windows':'PASS: exported Mac application online'))throw Error('Online application verification failed');
  if(!output.includes(peer?'PASS: live Mac-to-Windows':'PASS: exported Mac application online'))process.stdout.write(readFileSync(nativeLog,'utf8'));
} finally {
  if(app.exitCode===null)app.kill();service.kill();
  writeFileSync(join(artifacts,'online-app-service.log'),existsSync(join(fixture,'service.log'))?readFileSync(join(fixture,'service.log'),'utf8'):serviceLog);
}
