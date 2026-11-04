// Exercise the browser client's real socket/recovery code with a small DOM stub.
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const html = readFileSync(new URL('../src/main/resources/web/index.html', import.meta.url), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const elements = new Map();
const element = id => {
  if (!elements.has(id)) elements.set(id, {textContent: '', disabled: false, classList: {add() {}, remove() {}}});
  return elements.get(id);
};
class Socket {
  static OPEN = 1;
  constructor() { this.readyState = 1; this.sent = []; }
  send(value) { this.sent.push(JSON.parse(value)); }
}
const context = {
  WebSocket: Socket, location: {host: '127.0.0.1:7777'}, setTimeout() {},
  document: {getElementById: element, addEventListener() {}},
};
vm.runInNewContext(script + `
let opened = [];
openAsk = a => opened.push(a);
render = () => showNextAsk();
globalThis.harness = {
  deliver: m => ws.onmessage({data: JSON.stringify(m)}),
  answer, act, disconnect: () => ws.onclose(),
  get current() { return current; }, get asks() { return [...asks.keys()]; },
  get sent() { return ws.sent; }, get opened() { return opened; }
};`, context);
const h = context.harness;
let checks = 0;
function check(value, message) { assert.ok(value, message); checks++; }
const decision = (id, title = 'Pick') => ({id, kind: 'choose', title, min: 1, max: 1, options: [{label: 'A'}]});
const state = (revision, asks = [], sessionId = 'session-A') => ({type: 'state', protocolVersion: 2, sessionId, revision, asks});
h.deliver(state(1, [decision(1)]));
h.answer([0]);
check(h.current?.id === 1, 'Submitted dialog closed before confirmation');
check(h.sent[0].sessionId === 'session-A' && h.sent[0].protocolVersion === 2 && h.sent[0].revision === 1, 'Missing request metadata');
h.answer([0]); check(h.sent.length === 1, 'Duplicate pending answer sent');
h.deliver({type: 'error', requestId: h.sent[0].requestId, code: 'invalid_request', message: 'Try again'});
check(h.current?.id === 1, 'Rejected answer lost the dialog');
h.answer([0]); check(h.sent.length === 2, 'Rejected answer could not be corrected');
h.deliver({type: 'ack', requestId: h.sent[1].requestId});
check(h.current?.id === 1, 'Ack closed the dialog before authoritative removal');
h.deliver(state(2));
check(h.current === null && h.asks.length === 0, 'Snapshot did not remove a missed askClosed');
h.deliver(state(3, [decision(2)]));
h.deliver({type: 'askClosed', id: 2}); check(h.current === null, 'askClosed did not close the dialog');
h.act('ok'); h.act('ok');
check(h.sent.length === 3, 'Two clicks were sent against one revision');
h.deliver(state(4)); h.act('ok'); check(h.sent.length === 4, 'New revision did not permit another action');
h.deliver(state(5, [decision(1, 'Old dialog')]));
h.disconnect();
check(elements.get('btnOk').disabled, 'Disconnect left controls enabled');
// A process restart can reuse the decision integer; session identity must invalidate the old dialog.
h.deliver(state(1, [decision(1, 'New dialog')], 'session-B'));
check(h.current?.title === 'New dialog', 'Restart with reused decision ID preserved stale dialog');
console.log(`PASS: ${checks} browser protocol/recovery checks`);
