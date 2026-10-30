'use strict';
// Cœur du relais coop de RaidersGo, indépendant du transport (Node + ws, ou Cloudflare Workers).
// Protocole, règles et messages : voir relay.js (en-tête) et README.md. Ce module ne touche ni au
// réseau ni à `crypto` de Node : chaque hôte fournit ses connexions et son hasard.
//
// Connexion (fournie par l'hôte) : { send(data, binary), close(code, reason), terminate(), isOpen() }
//   - data : string (trame texte) ou Uint8Array / Buffer / ArrayBuffer (trame binaire).
// Hasard (options) : randomInt(n) -> entier dans [0, n[ ; randomToken() -> chaîne hexadécimale.

const PROTOCOL_VERSION = 1;
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // sans I, L, O, 0, 1 (ambigus)
const CODE_LEN = 6;
const CODE_RE = new RegExp('^[' + CODE_ALPHABET + ']{' + CODE_LEN + '}$');

/** Code saisi par un joueur -> forme canonique (majuscules, sans espaces ni tirets). */
function normalizeCode(s) {
  return String(s == null ? '' : s).toUpperCase().replace(/[^A-Z0-9]/g, '');
}

function isValidCode(s) {
  return CODE_RE.test(String(s));
}

function defaultRandomInt(n) {
  const a = new Uint32Array(1);
  globalThis.crypto.getRandomValues(a);
  return a[0] % n;
}

function defaultRandomToken() {
  const a = new Uint8Array(12);
  globalThis.crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** Code aléatoire non présent dans `taken` (Set ou Map). */
function generateCode(taken, randInt = defaultRandomInt) {
  for (let attempt = 0; attempt < 1000; attempt++) {
    let c = '';
    for (let i = 0; i < CODE_LEN; i++) c += CODE_ALPHABET[randInt(CODE_ALPHABET.length)];
    if (!taken.has(c)) return c;
  }
  throw new Error('no_code_available');
}

function cleanName(s) {
  const n = String(s == null ? '' : s).replace(/[\u0000-\u001f]/g, '').trim().slice(0, 20);
  return n || 'Raider';
}

function textOf(data) {
  if (typeof data === 'string') return data;
  if (data instanceof ArrayBuffer) return new TextDecoder().decode(new Uint8Array(data));
  return new TextDecoder().decode(data);
}

class RelayCore {
  constructor(opts = {}) {
    this.hostGraceMs = opts.hostGraceMs != null ? opts.hostGraceMs : 15000;
    this.guestGraceMs = opts.guestGraceMs != null ? opts.guestGraceMs : 20000;
    this.roomTtlMs = opts.roomTtlMs != null ? opts.roomTtlMs : 6 * 3600 * 1000;
    this.maxRooms = opts.maxRooms != null ? opts.maxRooms : 5000;
    this.maxMsgPerSec = opts.maxMsgPerSec != null ? opts.maxMsgPerSec : 300;
    this.maxQueued = opts.maxQueued != null ? opts.maxQueued : 256;
    this.maxPayload = opts.maxPayload != null ? opts.maxPayload : 64 * 1024;
    this.randomInt = opts.randomInt || defaultRandomInt;
    this.randomToken = opts.randomToken || defaultRandomToken;
    this.log = opts.log || (() => {});
    this.rooms = new Map(); // code -> room
    this.clients = new Set();
    this._nextId = 1;
  }

  stats() {
    return { ok: true, v: PROTOCOL_VERSION, rooms: this.rooms.size, clients: this.clients.size };
  }

  /** Nouvelle connexion : renvoie l'objet client à repasser à onMessage / onClose. */
  onOpen(conn, info) {
    const client = {
      id: this._nextId++, conn, alive: true, lastSeen: Date.now(), hello: false, room: null, role: null,
      name: 'Raider', msgWindow: Date.now(), msgCount: 0,
    };
    this.clients.add(client);
    this.log('connexion', client.id, info || '');
    return client;
  }

  _send(client, obj) {
    if (client && client.conn.isOpen()) client.conn.send(JSON.stringify(obj), false);
  }

  _error(client, code, message) {
    this._send(client, { t: 'error', code, message: message || code });
  }

  _rateOk(client) {
    const now = Date.now();
    if (now - client.msgWindow >= 1000) {
      client.msgWindow = now;
      client.msgCount = 0;
    }
    client.msgCount++;
    return client.msgCount <= this.maxMsgPerSec;
  }

  onMessage(client, data, isBinary) {
    client.alive = true;
    client.lastSeen = Date.now();
    if (!this._rateOk(client)) {
      this._error(client, 'rate', 'Trop de messages');
      client.conn.close(4008, 'rate');
      return;
    }
    const size = typeof data === 'string' ? data.length : (data.byteLength != null ? data.byteLength : data.length);
    if (size > this.maxPayload) {
      client.conn.close(4009, 'too_big');
      return;
    }
    if (isBinary) {
      if (!client.hello || !client.room) return;
      this._forward(client, data, true);
      return;
    }
    let msg;
    try {
      msg = JSON.parse(textOf(data));
    } catch (e) {
      this._error(client, 'bad_json');
      return;
    }
    if (!msg || typeof msg.t !== 'string') {
      this._error(client, 'bad_json');
      return;
    }
    if (!client.hello) {
      if (msg.t !== 'hello') {
        this._error(client, 'hello_required');
        return;
      }
      if (Number(msg.v) !== PROTOCOL_VERSION) {
        this._send(client, { t: 'error', code: 'version', message: 'Version du protocole différente', server_v: PROTOCOL_VERSION });
        client.conn.close(4001, 'version');
        return;
      }
      client.hello = true;
      this._send(client, { t: 'welcome', v: PROTOCOL_VERSION, id: client.id });
      return;
    }
    switch (msg.t) {
      case 'create': return this._create(client, msg);
      case 'join': return this._join(client, msg);
      case 'resume': return this._resume(client, msg);
      case 'leave': return this._leave(client, 'left');
      case 'relay':
        if (!client.room) return this._error(client, 'not_in_room');
        return this._forward(client, JSON.stringify({ t: 'relay', d: msg.d }), false);
      case 'ping': return this._send(client, { t: 'pong', ts: msg.ts, now: Date.now() });
      default: return this._error(client, 'unknown', 'Message inconnu : ' + msg.t);
    }
  }

  // --- Salons -------------------------------------------------------------------------

  _newSlot(client, name) {
    return { client, token: this.randomToken(), name, connected: true, timer: null, queue: [] };
  }

  _create(client, msg) {
    if (client.room) this._leave(client, 'left');
    if (this.rooms.size >= this.maxRooms) return this._error(client, 'server_full', 'Serveur plein');
    const code = generateCode(this.rooms, this.randomInt);
    client.name = cleanName(msg.name);
    const room = { code, created: Date.now(), host: this._newSlot(client, client.name), guest: null };
    this.rooms.set(code, room);
    client.room = room;
    client.role = 'host';
    this.log('salon créé', code, client.name);
    this._send(client, { t: 'created', code, token: room.host.token, role: 'host' });
  }

  _join(client, msg) {
    const code = normalizeCode(msg.code);
    if (!isValidCode(code)) return this._error(client, 'bad_code', 'Code invalide');
    const room = this.rooms.get(code);
    if (!room) return this._error(client, 'not_found', 'Salon introuvable');
    if (room.host.client === client) return this._error(client, 'full', 'Tu es déjà l\'hôte de ce salon');
    if (room.guest) return this._error(client, 'full', 'Salon plein');
    if (client.room) this._leave(client, 'left');
    client.name = cleanName(msg.name);
    room.guest = this._newSlot(client, client.name);
    client.room = room;
    client.role = 'guest';
    this.log('salon rejoint', code, client.name);
    this._send(client, {
      t: 'joined', code, token: room.guest.token, role: 'guest',
      peer: { name: room.host.name, connected: room.host.connected },
    });
    this._send(room.host.client, { t: 'peer_joined', name: client.name });
  }

  _resume(client, msg) {
    const code = normalizeCode(msg.code);
    const room = this.rooms.get(code);
    if (!room) return this._error(client, 'not_found', 'Salon fermé');
    let role = null;
    if (room.host && room.host.token === msg.token) role = 'host';
    else if (room.guest && room.guest.token === msg.token) role = 'guest';
    if (!role) return this._error(client, 'bad_token', 'Reprise refusée');
    const slot = room[role];
    if (slot.client && slot.client !== client) {
      // Ancienne connexion encore ouverte (coupure non détectée) : remplacée.
      const old = slot.client;
      old.room = null;
      try { old.conn.terminate(); } catch (e) { /* ignore */ }
    }
    if (slot.timer) clearTimeout(slot.timer);
    slot.timer = null;
    slot.client = client;
    slot.connected = true;
    client.room = room;
    client.role = role;
    client.name = slot.name;
    const peer = role === 'host' ? room.guest : room.host;
    this._send(client, {
      t: 'resumed', code, role,
      peer: peer ? { name: peer.name, connected: peer.connected } : null,
    });
    for (const q of slot.queue) {
      if (client.conn.isOpen()) client.conn.send(q.data, q.binary);
    }
    slot.queue = [];
    if (peer && peer.client) this._send(peer.client, { t: 'peer_back' });
    this.log('reprise', code, role);
  }

  _peerSlot(client) {
    const room = client.room;
    if (!room) return null;
    return client.role === 'host' ? room.guest : room.host;
  }

  _forward(client, data, binary) {
    const peer = this._peerSlot(client);
    if (!peer) return;
    if (peer.connected && peer.client && peer.client.conn.isOpen()) {
      peer.client.conn.send(data, binary);
    } else if (peer.queue.length < this.maxQueued) {
      // Coéquipier en cours de reconnexion : on garde les messages pour la reprise.
      peer.queue.push({ data, binary });
    }
  }

  _clearTimers(room) {
    for (const s of [room.host, room.guest]) {
      if (s && s.timer) clearTimeout(s.timer);
    }
  }

  _closeRoom(room, reason) {
    this._clearTimers(room);
    this.rooms.delete(room.code);
    for (const s of [room.host, room.guest]) {
      if (s && s.client) {
        if (s.client.room === room) {
          s.client.room = null;
          s.client.role = null;
        }
      }
    }
    if (room.guest && room.guest.client) this._send(room.guest.client, { t: 'room_closed', reason });
    this.log('salon fermé', room.code, reason);
  }

  _removeGuest(room, reason) {
    const g = room.guest;
    if (!g) return;
    if (g.timer) clearTimeout(g.timer);
    if (g.client && g.client.room === room) {
      g.client.room = null;
      g.client.role = null;
    }
    room.guest = null;
    if (room.host.client) this._send(room.host.client, { t: 'peer_left', reason });
  }

  /** Départ volontaire : hôte -> salon fermé ; invité -> place libérée. */
  _leave(client, reason) {
    const room = client.room;
    if (!room) return;
    if (client.role === 'host') {
      this._closeRoom(room, reason === 'left' ? 'host_left' : reason);
    } else {
      this._removeGuest(room, reason);
    }
    client.room = null;
    client.role = null;
  }

  onClose(client) {
    if (!this.clients.delete(client)) return;
    const room = client.room;
    if (!room) return;
    const slot = client.role === 'host' ? room.host : room.guest;
    if (!slot || slot.client !== client) return;
    slot.client = null;
    slot.connected = false;
    const grace = client.role === 'host' ? this.hostGraceMs : this.guestGraceMs;
    const peer = this._peerSlot(client);
    if (peer && peer.client) this._send(peer.client, { t: 'peer_lost', grace_ms: grace });
    const role = client.role;
    slot.timer = setTimeout(() => {
      slot.timer = null;
      if (slot.connected) return;
      if (role === 'host') this._closeRoom(room, 'host_timeout');
      else this._removeGuest(room, 'timeout');
    }, grace);
  }

  /** Coupe les connexions silencieuses depuis plus de `idleMs` (hôtes sans ping natif). */
  closeIdle(idleMs) {
    const now = Date.now();
    for (const c of Array.from(this.clients)) {
      if (now - c.lastSeen > idleMs) {
        try { c.conn.terminate(); } catch (e) { /* ignore */ }
        this.onClose(c);
      }
    }
  }

  sweepRooms() {
    const now = Date.now();
    for (const room of Array.from(this.rooms.values())) {
      if (now - room.created > this.roomTtlMs) this._closeRoom(room, 'expired');
    }
  }

  /** Arrêt : salons vidés, connexions coupées. */
  shutdown() {
    for (const room of this.rooms.values()) this._clearTimers(room);
    this.rooms.clear();
    for (const c of this.clients) {
      try { c.conn.terminate(); } catch (e) { /* déjà fermé */ }
    }
    this.clients.clear();
  }
}

module.exports = { RelayCore, PROTOCOL_VERSION, CODE_ALPHABET, CODE_LEN, normalizeCode, isValidCode, generateCode, cleanName };
