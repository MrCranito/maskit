'use strict';
// Tests du relais : codes de salon, création / jonction, relais, erreurs, départ de l'hôte,
// reprise après coupure. Lancer : npm test (dans server/).

const test = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const { Relay, normalizeCode, isValidCode, generateCode, PROTOCOL_VERSION } = require('../relay');

// RELAY_URL=ws://127.0.0.1:8799 : mêmes tests contre un relais déjà lancé (ex. la version
// Cloudflare sous `wrangler dev`, délais de grâce à 300 ms : voir cloudflare/README.md).
const EXTERNAL = process.env.RELAY_URL || '';

async function startRelay(opts) {
  if (EXTERNAL) {
    const health = EXTERNAL.replace(/^ws/, 'http').replace(/\/$/, '') + '/health';
    return { url: EXTERNAL, rooms: async () => (await (await fetch(health)).json()).rooms, stop: async () => {} };
  }
  const relay = new Relay(Object.assign({ port: 0 }, opts));
  const port = await relay.start();
  return { url: `ws://127.0.0.1:${port}`, rooms: async () => relay.rooms.size, stop: () => relay.stop() };
}

function client(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const inbox = [];
    const waiters = [];
    ws.on('message', (data, isBinary) => {
      const m = isBinary ? { t: '__bin', data } : JSON.parse(data.toString());
      const i = waiters.findIndex((w) => w.pred(m));
      if (i >= 0) waiters.splice(i, 1)[0].resolve(m);
      else inbox.push(m);
    });
    ws.next = (pred, ms = 2000) => new Promise((res, rej) => {
      const p = typeof pred === 'string' ? (m) => m.t === pred : pred;
      const j = inbox.findIndex(p);
      if (j >= 0) return res(inbox.splice(j, 1)[0]);
      const timer = setTimeout(() => rej(new Error('timeout ' + pred)), ms);
      waiters.push({ pred: p, resolve: (m) => { clearTimeout(timer); res(m); } });
    });
    ws.sendj = (o) => ws.send(JSON.stringify(o));
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

async function hello(ws) {
  ws.sendj({ t: 'hello', v: PROTOCOL_VERSION });
  await ws.next('welcome');
}

test('codes de salon', () => {
  assert.strictEqual(normalizeCode(' ab-c d2 3 '), 'ABCD23');
  assert.ok(isValidCode('ABCD23'));
  assert.ok(!isValidCode('ABCD2'));
  assert.ok(!isValidCode('ABCDI3'), 'I est exclu');
  assert.ok(!isValidCode('ABCD03'), '0 est exclu');
  const taken = new Set();
  for (let i = 0; i < 200; i++) {
    const c = generateCode(taken);
    assert.ok(isValidCode(c));
    assert.ok(!taken.has(c));
    taken.add(c);
  }
});

test('salon : création, jonction, relais, erreurs, départ', async () => {
  const relay = await startRelay({ heartbeatMs: 60000 });
  const port = relay.url;
  try {
    const h = await client(port);
    // Version différente refusée.
    const bad = await client(port);
    bad.sendj({ t: 'hello', v: 999 });
    const e = await bad.next('error');
    assert.strictEqual(e.code, 'version');

    await hello(h);
    h.sendj({ t: 'create', name: 'Alice' });
    const created = await h.next('created');
    assert.ok(isValidCode(created.code));

    const g = await client(port);
    await hello(g);
    g.sendj({ t: 'join', code: 'ZZZZ' });
    assert.strictEqual((await g.next('error')).code, 'bad_code');
    g.sendj({ t: 'join', code: 'ZZZZZZ' });
    assert.strictEqual((await g.next('error')).code, 'not_found');
    g.sendj({ t: 'join', code: created.code.toLowerCase(), name: 'Bob' });
    const joined = await g.next('joined');
    assert.strictEqual(joined.peer.name, 'Alice');
    assert.strictEqual((await h.next('peer_joined')).name, 'Bob');

    const third = await client(port);
    await hello(third);
    third.sendj({ t: 'join', code: created.code });
    assert.strictEqual((await third.next('error')).code, 'full');

    // Relais JSON et binaire dans les deux sens.
    h.sendj({ t: 'relay', d: { k: 'map', seed: 42 } });
    assert.strictEqual((await g.next('relay')).d.seed, 42);
    g.send(Buffer.from([1, 2, 3]), { binary: true });
    const bin = await h.next('__bin');
    assert.deepStrictEqual([...bin.data], [1, 2, 3]);

    // Ping.
    h.sendj({ t: 'ping', ts: 123 });
    assert.strictEqual((await h.next('pong')).ts, 123);

    // L'hôte part : salon fermé pour l'invité.
    h.sendj({ t: 'leave' });
    assert.strictEqual((await g.next('room_closed')).reason, 'host_left');
    assert.strictEqual(await relay.rooms(), 0);
    for (const w of [h, g, bad, third]) w.close();
  } finally {
    await relay.stop();
  }
});

test('reprise après coupure et expiration du délai', async () => {
  const relay = await startRelay({ heartbeatMs: 60000, hostGraceMs: 300, guestGraceMs: 300 });
  const port = relay.url;
  try {
    const h = await client(port);
    await hello(h);
    h.sendj({ t: 'create', name: 'H' });
    const created = await h.next('created');
    const g = await client(port);
    await hello(g);
    g.sendj({ t: 'join', code: created.code, name: 'G' });
    const joined = await g.next('joined');
    await h.next('peer_joined');

    // L'invité coupe : l'hôte est prévenu, les messages sont gardés, reprise possible.
    g.terminate();
    const lost = await h.next('peer_lost');
    assert.strictEqual(lost.grace_ms, 300);
    h.send(Buffer.from([9]), { binary: true });
    const g2 = await client(port);
    await hello(g2);
    g2.sendj({ t: 'resume', code: created.code, token: joined.token });
    const res = await g2.next('resumed');
    assert.strictEqual(res.role, 'guest');
    const q = await g2.next('__bin');
    assert.deepStrictEqual([...q.data], [9]);
    await h.next('peer_back');

    // Coupure sans reprise : l'invité est exclu après le délai.
    g2.terminate();
    await h.next('peer_lost');
    assert.strictEqual((await h.next('peer_left', 2000)).reason, 'timeout');

    // Coupure de l'hôte sans reprise : salon fermé.
    const g3 = await client(port);
    await hello(g3);
    g3.sendj({ t: 'join', code: created.code, name: 'G3' });
    await g3.next('joined');
    h.terminate();
    await g3.next('peer_lost');
    assert.strictEqual((await g3.next('room_closed', 2000)).reason, 'host_timeout');
    g3.close();
  } finally {
    await relay.stop();
  }
});
