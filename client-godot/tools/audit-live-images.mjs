// Read-only: inspect public card descriptors; never submit a gameplay action.
import {readFileSync} from 'node:fs';
const manifest = JSON.parse(readFileSync(new URL('../assets/cards/manifest.json', import.meta.url), 'utf8'));
const socket = new WebSocket(process.argv[2] || 'ws://127.0.0.1:7777/ws');
const timer = setTimeout(() => {console.error('No live snapshot available'); socket.close(); process.exitCode = 1;}, 5000);
socket.onopen = () => socket.send(JSON.stringify({type:'hello'}));
socket.onerror = () => {clearTimeout(timer); console.error('No live bridge connection'); process.exitCode = 1;};
socket.onmessage = event => {
  const state = JSON.parse(event.data);
  if (state.type !== 'state' || !state.players) return;
  clearTimeout(timer);
  const missing = [], covered = [];
  for (const player of state.players) for (const [zone, cards] of Object.entries(player.zones)) for (const card of cards) {
    if (card.hidden || card.faceDown) continue;
    const entry = {name:card.name, imageKey:card.imageKey, zone, player:player.name};
    const rulesName = card.imageKey?.startsWith('c:') && !card.imageKey.includes('$') ? card.imageKey.slice(2).split('|')[0] : '';
    (manifest.byKey[card.imageKey] || manifest.byName[card.name] || manifest.byName[rulesName] ? covered : missing).push(entry);
  }
  console.log(JSON.stringify({covered:covered.length, missing, prompt:state.prompt, stack:state.stack}, null, 2));
  socket.close();
};
