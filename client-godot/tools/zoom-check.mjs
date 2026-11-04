// Native rendering regression: compare the final monitor image with fullscreen.
import {spawn} from 'node:child_process';
import {mkdirSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const root=fileURLToPath(new URL('../..',import.meta.url));
const artifacts=join(root,'client-godot/artifacts');
mkdirSync(artifacts,{recursive:true});writeFileSync(join(artifacts,'.gdignore'),'');
const godot=spawn(process.env.FORGE_GODOT_PATH||join(root,process.platform==='darwin'?'.tools/godot/Godot.app/Contents/MacOS/Godot':'.tools/godot/Godot_v4.7.2-stable_win64.exe'),['--path',join(root,'client-godot'),'--script','res://tests/MonitorZoomChecks.gd','--resolution','1600x1000',...(process.platform==='darwin'?[]:['--position','-20000,-20000'])],{cwd:root,windowsHide:true});
let output='',errors='';
godot.stdout.on('data',b=>{output+=b;process.stdout.write(b)});
godot.stderr.on('data',b=>{errors+=b;process.stderr.write(b);if(/SCRIPT ERROR:|Parse Error:|Failed to load script/.test(errors))godot.kill()});
try {
  const code=await new Promise((ok,fail)=>{const timer=setTimeout(()=>{godot.kill();fail(Error('Zoom check timed out'))},60000);godot.on('error',e=>{clearTimeout(timer);fail(e)});godot.on('exit',c=>{clearTimeout(timer);ok(c)})});
  writeFileSync(join(artifacts,'zoom-check.stdout.log'),output);writeFileSync(join(artifacts,'zoom-check.stderr.log'),errors);
  if(code!==0||/SCRIPT ERROR:|ERROR:/.test(errors)||!output.includes('PASS: monitor zoom continuity'))throw Error('Zoom rendering verification failed');
} catch(error){console.error(error);process.exitCode=1}
