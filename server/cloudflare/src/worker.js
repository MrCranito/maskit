// Relais coop de RaidersGo sur Cloudflare Workers + Durable Objects.
// Même protocole et même logique que le serveur Node : le cœur est partagé (../../relay_core.js).
//  - GET /health (ou /)            -> {ok, v, rooms, clients}
//  - WebSocket sur n'importe quel chemin -> relais (salons à code, voir ../../relay.js)
// Toutes les connexions vont au même Durable Object (« global ») : les salons sont choisis APRÈS
// la connexion (messages create / join), il faut donc un seul endroit qui les connaît tous.
import core from '../../relay_core.js';

export class RelayHub {
  constructor(state, env) {
    this.state = state;
    const n = (k, d) => (env[k] != null && env[k] !== '' ? Number(env[k]) : d);
    this.idleMs = n('IDLE_TIMEOUT_MS', 30000);
    this.core = new core.RelayCore({
      hostGraceMs: n('HOST_GRACE_MS', 15000),
      guestGraceMs: n('GUEST_GRACE_MS', 20000),
      maxRooms: n('MAX_ROOMS', 5000),
      log: env.LOG === '1' ? (...a) => console.log(...a) : () => {},
    });
    this.timers = null;
  }

  async fetch(request) {
    if (request.headers.get('Upgrade') !== 'websocket') {
      return Response.json(this.core.stats());
    }
    const pair = new WebSocketPair();
    const [clientSide, server] = Object.values(pair);
    server.accept();
    const conn = {
      send: (data) => server.send(data),
      close: (code, reason) => { try { server.close(code, reason); } catch (e) { /* déjà fermé */ } },
      terminate: () => { try { server.close(1000, 'terminate'); } catch (e) { /* déjà fermé */ } },
      isOpen: () => server.readyState === 1,
    };
    const client = this.core.onOpen(conn, request.headers.get('CF-Connecting-IP') || '');
    try { server.binaryType = 'arraybuffer'; } catch (e) { /* propriété absente : Blob converti ci-dessous */ }
    // Trames binaires : ArrayBuffer, ou Blob selon le runtime. Conversion asynchrone en gardant
    // l'ordre des messages (file par connexion).
    let chain = Promise.resolve();
    server.addEventListener('message', (ev) => {
      const data = ev.data;
      if (typeof data === 'string' || data instanceof ArrayBuffer) {
        chain = chain.then(() => this.core.onMessage(client, data, typeof data !== 'string'));
      } else {
        chain = chain.then(async () => this.core.onMessage(client, await data.arrayBuffer(), true));
      }
    });
    server.addEventListener('close', () => { this.core.onClose(client); this._maybeStopTimers(); });
    server.addEventListener('error', () => { this.core.onClose(client); this._maybeStopTimers(); });
    this._startTimers();
    return new Response(null, { status: 101, webSocket: clientSide });
  }

  // Pas de ping natif côté Worker : on coupe les connexions muettes, on expire les vieux salons.
  _startTimers() {
    if (this.timers) return;
    this.timers = [
      setInterval(() => this.core.closeIdle(this.idleMs), 5000),
      setInterval(() => this.core.sweepRooms(), 60000),
    ];
  }

  _maybeStopTimers() {
    if (!this.timers || this.core.clients.size > 0 || this.core.rooms.size > 0) return;
    for (const t of this.timers) clearInterval(t);
    this.timers = null;
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const hub = env.RELAY.get(env.RELAY.idFromName('global'));
    if (request.headers.get('Upgrade') === 'websocket') return hub.fetch(request);
    if (url.pathname === '/health' || url.pathname === '/') return hub.fetch(new Request(url.origin + '/health'));
    return new Response('not found', { status: 404 });
  },
};
