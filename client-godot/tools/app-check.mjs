// Exercises the actual main menu, editor and separately owned Commander engine.
import {spawn,spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdirSync,mkdtempSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join,delimiter} from 'node:path';
const root=fileURLToPath(new URL('../..',import.meta.url));
const artifacts=join(root,'client-godot/artifacts');
mkdirSync(artifacts,{recursive:true});writeFileSync(join(artifacts,'.gdignore'),'');
const fixture=mkdtempSync(join(artifacts,'app-fixture-'));
writeFileSync(join(fixture,'Atraxa.dck'),"[metadata]\nName=Atraxa menu test\n[Commander]\n1 Atraxa, Praetors' Voice|PF26|1\n[Main]\n99 Forest|SOS|1\n");
writeFileSync(join(fixture,'Unfinished.dck'),"[metadata]\nName=Unfinished deck\n[Main]\n1 Forest|SOS|1\n");
for(let i=1;i<=16;i++)writeFileSync(join(fixture,`Deck-${String(i).padStart(2,'0')}.dck`),`[metadata]\nName=Commander ${String(i).padStart(2,'0')}\n[Commander]\n1 Atraxa, Praetors' Voice|PF26|1\n[Main]\n99 Forest|SOS|1\n`);
const socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const port=socket.address().port;await new Promise(r=>socket.close(r));
const jvm=spawnSync('java',['-XshowSettings:properties','-version'],{encoding:'utf8',windowsHide:true});
const home=jvm.stderr.match(/^\s*java.home = (.+)$/m)?.[1].trim();if(!home)throw Error('Cannot locate Java');
const startupFile=join(fixture,'startup.json');
writeFileSync(startupFile,JSON.stringify({stage:'starting',title:'Starting Forge',detail:'Preparing the game library. This can take a minute.'}));
const startupFailure=process.argv.includes('--startup-failure');
const menuPreview=process.argv.includes('--menu-preview');
const editorPreview=process.argv.includes('--editor-preview');
const nightBaseline=process.argv.includes('--night-baseline');
const nightReview=process.argv.includes('--night-review');
const nightCinematics=process.argv.includes('--night-cinematics');
let log='',godot,bridge;const childPids=new Set();
const startBridge=()=>{
  if(bridge)return;
  bridge=spawn(join(home,'bin',process.platform==='win32'?'java.exe':'java'),['-Xmx4g','-cp',['target/classes','target/lib/*'].join(delimiter),'forgeui.bridge.LibraryMain','--assets','../forge/forge-gui','--port',String(port),'--library-root',startupFailure?join(fixture,'Atraxa.dck'):fixture,'--startup-status',startupFile],{cwd:join(root,'bridge'),windowsHide:true});
  for(const stream of [bridge.stdout,bridge.stderr])stream.on('data',b=>{log+=b;writeFileSync(join(artifacts,startupFailure?'app-startup-failure-bridge.log':'app-bridge.log'),log)});
};
try {
  const render=process.argv.includes('--render');
  // FORGE_EXPORTED_EXE checks a packaged build; release binaries refuse --path and carry the project inside.
  godot=spawn(process.env.FORGE_EXPORTED_EXE||process.env.FORGE_GODOT_PATH||join(root,process.platform==='darwin'?'.tools/godot/Godot.app/Contents/MacOS/Godot':'.tools/godot/Godot_v4.7.2-stable_win64.exe'),[...(process.env.FORGE_EXPORTED_EXE?[]:['--path',join(root,'client-godot')]),...(render?['--resolution','1600x1000',...(process.platform==='darwin'?[]:['--position','-20000,-20000'])]:['--headless']),'--',`--library-url=ws://127.0.0.1:${port}/ws`,'--app-check',...(startupFailure?['--app-startup-failure']:[]),...(menuPreview?['--app-menu-preview']:[]),...(editorPreview?['--app-editor-preview']:[]),...(nightBaseline?['--app-night-baseline']:[]),...(nightReview?['--app-night-review']:[]),...(nightCinematics?['--app-night-cinematics']:[]),`--startup-status=${startupFile}`,`--library-fixture=${fixture}`,`--app-capture=${render?artifacts:''}`],{cwd:root,windowsHide:true});
  let output='',errors='';
  godot.stdout.on('data',b=>{output+=b;process.stdout.write(b);if(output.includes('APP STARTUP VISIBLE'))startBridge();for(const m of output.matchAll(/APP MATCH PID: (\d+)/g))childPids.add(Number(m[1]))});
  godot.stderr.on('data',b=>{errors+=b;process.stderr.write(b);if(/SCRIPT ERROR:|Parse Error:|Failed to load script/.test(errors))godot.kill()});
  const code=await new Promise((ok,fail)=>{const timer=setTimeout(()=>fail(Error('Application check timed out')),360000);godot.on('error',e=>{clearTimeout(timer);fail(e)});godot.on('exit',c=>{clearTimeout(timer);ok(c)})});
  writeFileSync(join(artifacts,startupFailure?'app-startup-failure.stdout.log':'app.stdout.log'),output);writeFileSync(join(artifacts,startupFailure?'app-startup-failure.stderr.log':'app.stderr.log'),errors);
  if(code!==0||/SCRIPT ERROR:|ERROR:/.test(errors)||!output.includes(startupFailure?'PASS: startup failure screen':(nightBaseline||nightReview)?'PASS: night lighting captures':menuPreview?'PASS: computer menu preview':editorPreview?'PASS: carousel editor preview':'PASS: application navigation'))throw Error('Application verification failed');
  for(const pid of childPids){let alive=true;try{process.kill(pid,0)}catch{alive=false}if(alive)throw Error(`Owned match ${pid} survived leaving the game`)}
}catch(error){console.error(error);console.error(log.slice(-2500));process.exitCode=1}
finally{if(godot&&godot.exitCode===null)godot.kill();if(bridge)bridge.kill(); /* child JVMs also watch this parent's lifetime */}
