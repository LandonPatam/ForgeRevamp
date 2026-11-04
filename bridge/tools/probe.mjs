// Dev tool: connect to the bridge, optionally send one message, print a compact summary of the result.
// node probe.mjs                         -> summary
// node probe.mjs action ok|cancel|card <id>|player <id>
// node probe.mjs answer <askId> <json>
const [, , kind, a1, a2] = process.argv;
const ws = new WebSocket(process.env.FORGE_BRIDGE_URL || 'ws://127.0.0.1:7777/ws');
let state = null;
const asks = new Map();
ws.onmessage = e => {
  const m = JSON.parse(e.data);
  if (m.type === 'state') { state = m; asks.clear(); (m.asks || []).forEach(a => asks.set(a.id, a)); }
  if (m.type === 'ask') asks.set(m.id, m);
  if (m.type === 'askClosed') asks.delete(m.id);
  if (m.type === 'error') { console.error(`${m.code}: ${m.message}`); process.exit(1); }
};
ws.onopen = () => {
  ws.send(JSON.stringify({ type: 'hello' }));
  setTimeout(() => {
    if (kind && (!state || state.loading)) { console.error('Bridge is not ready'); process.exit(1); }
    const context = state ? {requestId: 'probe-1', protocolVersion: state.protocolVersion, sessionId: state.sessionId, revision: state.revision} : {};
    if (kind === 'action') ws.send(JSON.stringify({ ...context, type: 'action', action: a1, id: a2 === undefined ? undefined : +a2 }));
    if (kind === 'answer') ws.send(JSON.stringify({ ...context, type: 'answer', id: +a1, value: JSON.parse(a2) }));
    setTimeout(print, kind ? 2500 : 300);
  }, 700);
};
function print() {
  if (!state || state.loading) { console.log('no state yet'); process.exit(0); }
  const g = state.game, p = state.prompt;
  console.log(`T${g.turn} ${g.phase} active=${g.activePlayer} gameOver=${g.gameOver} ${g.winner ?? ''}`);
  console.log(`PROMPT: ${p.message.replace(/\n/g, ' | ')}  [ok:${p.okEnabled ? p.okLabel : '-'}] [cancel:${p.cancelEnabled ? p.cancelLabel : '-'}] selectable=${JSON.stringify(p.selectable)} targets=${JSON.stringify(p.targets)}`);
  for (const pl of state.players) {
    const z = pl.zones;
    const names = arr => arr.map(c => c.hidden ? '?' : `${c.name}#${c.id}${c.tapped ? 'T' : ''}`).join(', ');
    console.log(`- ${pl.id === state.me ? '*' : ' '}${pl.name} [${pl.id}] life=${pl.life} lib=${pl.libraryCount} hand=${pl.handCount}${pl.lost ? ' LOST' : ''}`);
    console.log(`    cmd: ${names(z.Command)}`);
    console.log(`    bf: ${names(z.Battlefield)}`);
    if (pl.id === state.me) console.log(`    hand: ${names(z.Hand)}`);
  }
  if (state.stack.length) console.log('STACK:', state.stack.map(s => s.text).join(' || '));
  for (const a of asks.values()) console.log(`ASK #${a.id} ${a.kind} "${a.title}" "${a.message}" min=${a.min} max=${a.max} opts=${(a.options || []).map((o, i) => `${i}:${o.label}`).join(' / ')}`);
  console.log('LOG:', state.log.slice(0, 4).join(' || '));
  process.exit(0);
}
