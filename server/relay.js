'use strict';
// Serveur relais du mode coop de RaidersGo (hébergement Node : Fly.io, Render, VPS…).
// La logique des salons est dans relay_core.js, partagée avec la version Cloudflare Workers
// (cloudflare/src/worker.js) : ce fichier ne fait que la brancher sur HTTP + ws.
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
const core = require('./relay_core');

class Relay extends core.RelayCore {
  constructor(opts = {}) {
    super(Object.assign({
      randomInt: (n) => crypto.randomInt(n),
      randomToken: () => crypto.randomBytes(12).toString('hex'),
    }, opts));
    this.port = opts.port != null ? opts.port : 8787;
    this.host = opts.host || '0.0.0.0';
    this.heartbeatMs = opts.heartbeatMs != null ? opts.heartbeatMs : 10000;
    this.server = null;
    this.wss = null;
    this._hb = null;
    this._sweep = null;
  }

  start() {
    return new Promise((resolve, reject) => {
      this.server = http.createServer((req, res) => this._http(req, res));
      this.wss = new WebSocketServer({ server: this.server, maxPayload: this.maxPayload });
      this.wss.on('connection', (ws, req) => this._onConnection(ws, req));
      this.server.once('error', reject);
      this.server.listen(this.port, this.host, () => {
        this.port = this.server.address().port;
        this._hb = setInterval(() => this._heartbeat(), this.heartbeatMs);
        this._sweep = setInterval(() => this.sweepRooms(), 60000);
        resolve(this.port);
      });
    });
  }

  stop() {
    clearInterval(this._hb);
    clearInterval(this._sweep);
    this.shutdown();
    return new Promise((resolve) => {
      if (!this.server) return resolve();
      this.wss.close(() => this.server.close(() => resolve()));
    });
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
    const conn = {
      send: (data, binary) => ws.send(data, { binary }),
      close: (code, reason) => ws.close(code, reason),
      terminate: () => ws.terminate(),
      isOpen: () => ws.readyState === 1,
    };
    const client = this.onOpen(conn, req && req.socket ? req.socket.remoteAddress : '');
    client.ws = ws;
    ws.on('pong', () => { client.alive = true; });
    ws.on('message', (data, isBinary) => this.onMessage(client, data, isBinary));
    ws.on('close', () => this.onClose(client));
    ws.on('error', () => { /* géré par close */ });
  }

  _heartbeat() {
    for (const c of this.clients) {
      if (!c.alive) {
        try { c.conn.terminate(); } catch (e) { /* ignore */ }
        continue;
      }
      c.alive = false;
      try { c.ws.ping(); } catch (e) { /* ignore */ }
    }
  }
}

module.exports = {
  Relay,
  PROTOCOL_VERSION: core.PROTOCOL_VERSION,
  CODE_ALPHABET: core.CODE_ALPHABET,
  CODE_LEN: core.CODE_LEN,
  normalizeCode: core.normalizeCode,
  isValidCode: core.isValidCode,
  generateCode: core.generateCode,
  cleanName: core.cleanName,
};
