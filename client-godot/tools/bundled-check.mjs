// Checks the shipped Mac app's own bundled service and real match child from an unrelated cwd.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {randomUUID} from 'node:crypto';
const executable=resolve(process.argv[2]||'dist/ForgeUI-mac-optimized/ForgeUI.app/Contents/MacOS/ForgeUI');
const probe=createServer();
await new Promise(r=>probe.listen(0,'127.0.0.1',r));
const port=probe.address().port;
await new Promise(r=>probe.close(r));
const intel=process.argv.includes('--intel');
const app=spawn(intel?'/usr/bin/arch':executable,
  [...(intel?['-x86_64',executable]:[]),'--headless','--',`--service-port=${port}`],
  {cwd:tmpdir()});
let output='',library,game;
for(const stream of [app.stdout,app.stderr])stream.on('data',b=>{output+=b;process.stdout.write(b)});
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const owner=randomUUID();
async function connect(url) {
  const ws=new WebSocket(url);
  await new Promise((ok,fail)=>{
    const timer=setTimeout(()=>{ws.close();fail(Error('Connect timeout'))},1500);
    ws.onopen=()=>{clearTimeout(timer);ok()};
    ws.onerror=()=>{clearTimeout(timer);fail(Error('Not ready'))};
  });
  return ws;
}
let next=0;
function request(op,args={}) {
  return new Promise((ok,fail)=>{
    const requestId=++next;
    const timer=setTimeout(()=>{library.removeEventListener('message',receive);fail(Error(`Timed out: ${op}`))},90000);
    function receive(event) {
      const reply=JSON.parse(event.data);
      if(reply.requestId!==requestId)return;
      clearTimeout(timer);library.removeEventListener('message',receive);
      if(!reply.ok)fail(Error(reply.error));else ok(reply.result);
    }
    library.addEventListener('message',receive);
    library.send(JSON.stringify({requestId,op,owner,...args}));
  });
}
try {
  for(let i=0;i<120&&!library;i++) {
    if(app.exitCode!==null)throw Error(`App exited: ${app.exitCode}`);
    try{library=await connect(`ws://127.0.0.1:${port}/ws`)}catch{await pause(1000)}
  }
  assert(library,'Bundled service did not start');
  const catalog=await request('list');
  const deck=catalog.decks.find(d=>d.source==='precon'&&d.legal);
  assert(deck,'No bundled legal Commander precon');
  console.log(`PASS: bundled Java service and card catalog (${catalog.decks.length} decks)`);
  const launchKey=randomUUID();
  let match=await request('match.start',{id:deck.id,launchKey,setup:{
    human:{name:'Mac package check',avatar:0},
    bots:[{name:'Package bot',avatar:1,mode:'saved',deckId:deck.id}]
  }});
  for(let i=0;i<120&&match.state==='starting';i++) {
    await pause(1000);match=await request('match.status');
  }
  assert.equal(match.state,'ready',JSON.stringify(match));
  let snapshot;
  game=new WebSocket(match.url);
  await new Promise((ok,fail)=>{
    const timer=setTimeout(()=>fail(Error('No real game snapshot')),60000);
    game.onmessage=event=>{
      const message=JSON.parse(event.data);
      if(message.type==='state'&&!message.loading){snapshot=message;clearTimeout(timer);ok()}
    };
    game.onerror=()=>{clearTimeout(timer);fail(Error('Match connection failed'))};
  });
  assert.equal(snapshot.protocolVersion,2);
  assert.equal(snapshot.players.length,2);
  assert(snapshot.players.filter(p=>p.id!==snapshot.me).every(p=>p.zones.Hand.every(c=>c.hidden)));
  console.log(`PASS: real Commander match using bundled runtime and assets (${deck.name})`);
  game.close();
  const stopped=await request('match.stop',{session:match.session,launchKey});
  assert.equal(stopped.state,'stopped');
  assert(!/SCRIPT ERROR:|Parse Error:|Failed to load script/.test(output));
  const closed=new Promise((ok,fail)=>{
    const timer=setTimeout(()=>fail(Error('Bundled service survived its app')),15000);
    library.addEventListener('close',()=>{clearTimeout(timer);ok()},{once:true});
  });
  app.kill();
  await closed;
  console.log('PASS: owned match stop and bundled service cleanup on app exit');
} finally {
  game?.close();library?.close();
  if(app.exitCode===null)app.kill();
}
