'use strict';
// Serveur relais du mode coop de RaidersGo.
//
// Rôle : mettre en relation deux téléphones (hôte + invité) qui ne peuvent pas se joindre
// directement (NAT des box / 4G). Le serveur ne simule RIEN : il gère des salons à code de
// 6 caractères et relaie les messages entre les deux membres d'un salon.
//
// Transport : WebSocket (ws:// en local, wss:// en production derrière le TLS de l'hébergeur).
//  - trames TEXTE  = messages de contrôle JSON {"t": type, ...} (salon, ping, relais lobby) ;
//  - trames BINAIRES = données de jeu, relayées telles quelles à l'autre membre du salon.
//
// Contrôle (client -> serveur) :
//   hello  {v}              version du protocole (obligatoire en premier ; sinon refus)
//   create {name}           crée un salon -> created {code, token, role:"host"}
//   join   {code, name}     rejoint       -> joined  {code, token, role:"guest", peer}
//   resume {code, token}    reprise après coupure -> resumed {code, role, peer}
//   leave  {}               quitte (hôte : salon fermé pour l'invité)
//   relay  {d}              message JSON pour l'autre membre (lobby) -> relay {d}
//   ping   {ts}             -> pong {ts, now}
// Serveur -> client : welcome, error {code, message}, peer_joined, peer_left {reason},
//   peer_lost {grace_ms}, peer_back, room_closed {reason}.
// Codes d'erreur : version, hello_required, bad_json, bad_code, not_found, full, bad_token,
//   not_in_room, rate, server_full.

const http = require('http');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

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

/** Code aléatoire non présent dans `taken` (Set ou Map). */
function generateCode(taken, randInt = crypto.randomInt) {
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

class Relay {
  constructor(opts = {}) {
    this.port = opts.port != null ? opts.port : 8787;
    this.host = opts.host || '0.0.0.0';
    this.hostGraceMs = opts.hostGraceMs != null ? opts.hostGraceMs : 15000;
    this.guestGraceMs = opts.guestGraceMs != null ? opts.guestGraceMs : 20000;
    this.heartbeatMs = opts.heartbeatMs != null ? opts.heartbeatMs : 10000;
    this.roomTtlMs = opts.roomTtlMs != null ? opts.roomTtlMs : 6 * 3600 * 1000;
    this.maxRooms = opts.maxRooms != null ? opts.maxRooms : 5000;
    this.maxMsgPerSec = opts.maxMsgPerSec != null ? opts.maxMsgPerSec : 300;
    this.maxQueued = opts.maxQueued != null ? opts.maxQueued : 256;
    this.log = opts.log || (() => {});
    this.rooms = new Map(); // code -> room
    this.clients = new Set();
    this._nextId = 1;
    this.server = null;
    this.wss = null;
    this._hb = null;
    this._sweep = null;
  }

  start() {
    return new Promise((resolve, reject) => {
      this.server = http.createServer((req, res) => this._http(req, res));
      this.wss = new WebSocketServer({ server: this.server, maxPayload: 64 * 1024 });
      this.wss.on('connection', (ws, req) => this._onConnection(ws, req));
      this.server.once('error', reject);
      this.server.listen(this.port, this.host, () => {
        this.port = this.server.address().port;
        this._hb = setInterval(() => this._heartbeat(), this.heartbeatMs);
        this._sweep = setInterval(() => this._sweepRooms(), 60000);
        resolve(this.port);
      });
    });
  }

  stop() {
    clearInterval(this._hb);
    clearInterval(this._sweep);
    for (const room of this.rooms.values()) this._clearTimers(room);
    this.rooms.clear();
    for (const c of this.clients) {
      try { c.ws.terminate(); } catch (e) { /* déjà fermé */ }
    }
    this.clients.clear();
    return new Promise((resolve) => {
      if (!this.server) return resolve();
      this.wss.close(() => this.server.close(() => resolve()));
    });
  }

  stats() {
    return { ok: true, v: PROTOCOL_VERSION, rooms: this.rooms.size, clients: this.clients.size };
  }

  // --- HTTP (santé) ---------------------------------------------------------------

  _http(req, res) {
    if (req.url === '/health' || req.url === '/') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(this.stats()));
      return;
    }
    res.writeHead(404, { 'content-type': 'text/plain' });
    res.end('not found');
  }

  // --- Connexions -------------------------------------------------------------------

  _onConnection(ws, req) {
    const client = {
      id: this._nextId++, ws, alive: true, hello: false, room: null, role: null, name: 'Raider',
      msgWindow: Date.now(), msgCount: 0,
    };
    this.clients.add(client);
    this.log('connexion', client.id, req && req.socket ? req.socket.remoteAddress : '');
    ws.on('pong', () => { client.alive = true; });
    ws.on('message', (data, isBinary) => this._onMessage(client, data, isBinary));
    ws.on('close', () => this._onClose(client));
    ws.on('error', () => { /* géré par close */ });
  }

  _heartbeat() {
    for (const c of this.clients) {
      if (!c.alive) {
        try { c.ws.terminate(); } catch (e) { /* ignore */ }
        continue;
      }
      c.alive = false;
      try { c.ws.ping(); } catch (e) { /* ignore */ }
    }
  }

  _send(client, obj) {
    if (client && client.ws.readyState === 1) client.ws.send(JSON.stringify(obj));
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

  _onMessage(client, data, isBinary) {
    if (!this._rateOk(client)) {
      this._error(client, 'rate', 'Trop de messages');
      client.ws.close(4008, 'rate');
      return;
    }
    if (isBinary) {
      if (!client.hello || !client.room) return;
      this._forward(client, data, true);
      return;
    }
    let msg;
    try {
      msg = JSON.parse(data.toString('utf8'));
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
        client.ws.close(4001, 'version');
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
    return { client, token: crypto.randomBytes(12).toString('hex'), name, connected: true, timer: null, queue: [] };
  }

  _create(client, msg) {
    if (client.room) this._leave(client, 'left');
    if (this.rooms.size >= this.maxRooms) return this._error(client, 'server_full', 'Serveur plein');
    const code = generateCode(this.rooms);
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
      try { old.ws.terminate(); } catch (e) { /* ignore */ }
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
      if (client.ws.readyState === 1) client.ws.send(q.data, { binary: q.binary });
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
    if (peer.connected && peer.client && peer.client.ws.readyState === 1) {
      peer.client.ws.send(data, { binary });
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

  _onClose(client) {
    this.clients.delete(client);
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

  _sweepRooms() {
    const now = Date.now();
    for (const room of Array.from(this.rooms.values())) {
      if (now - room.created > this.roomTtlMs) this._closeRoom(room, 'expired');
    }
  }
}

module.exports = { Relay, PROTOCOL_VERSION, CODE_ALPHABET, CODE_LEN, normalizeCode, isValidCode, generateCode, cleanName };
