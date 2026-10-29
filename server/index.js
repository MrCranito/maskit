'use strict';
// Point d'entrée du serveur relais (voir relay.js et README.md).
// Variables d'environnement :
//   PORT           port d'écoute (défaut 8787 ; Render/Fly/Railway le fournissent)
//   HOST           interface (défaut 0.0.0.0)
//   HOST_GRACE_MS  délai de reconnexion de l'hôte avant fermeture du salon (défaut 15000)
//   GUEST_GRACE_MS délai de reconnexion de l'invité avant son exclusion (défaut 20000)
//   MAX_ROOMS      nombre maximal de salons simultanés (défaut 5000)
//   LOG            1 = journal des salons sur la sortie standard

const { Relay, PROTOCOL_VERSION } = require('./relay');

const env = process.env;
const log = env.LOG === '1'
  ? (...a) => console.log(new Date().toISOString(), ...a)
  : () => {};

const relay = new Relay({
  port: Number(env.PORT || 8787),
  host: env.HOST || '0.0.0.0',
  hostGraceMs: Number(env.HOST_GRACE_MS || 15000),
  guestGraceMs: Number(env.GUEST_GRACE_MS || 20000),
  maxRooms: Number(env.MAX_ROOMS || 5000),
  log,
});

relay.start().then((port) => {
  console.log(`RaidersGo relais prêt sur le port ${port} (protocole v${PROTOCOL_VERSION})`);
}).catch((e) => {
  console.error('Démarrage impossible :', e.message);
  process.exit(1);
});

function shutdown() {
  relay.stop().then(() => process.exit(0));
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
