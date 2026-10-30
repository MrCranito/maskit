# Relais coop sur Cloudflare Workers

Même relais que le serveur Node (`../relay.js`), hébergé sur Cloudflare : un Worker reçoit les
connexions et les passe à **un seul Durable Object** (`RelayHub`, nommé « global »). Celui-ci fait
tourner le même cœur que le serveur Node (`../relay_core.js`) : mêmes salons à code, même
protocole, mêmes erreurs, même reprise après coupure. Le jeu ne change pas : seule l'URL change.

Pourquoi un seul Durable Object : le salon est choisi **après** la connexion (`create` / `join`),
il faut donc un endroit unique qui connaît tous les salons. Un Durable Object tient sans peine des
centaines de salons (2 joueurs, 3 à 6 ko/s chacun). Les salons sont en mémoire, sans stockage :
si Cloudflare redémarre l'objet (mise à jour, rare), les parties en cours sont coupées, comme
avec un redémarrage du serveur Node.

Différence avec Node : pas de ping WebSocket natif côté Worker. Une connexion muette depuis
`IDLE_TIMEOUT_MS` (30 s) est coupée ; le jeu envoie un ping toutes les 2 s (`[net] ping_interval`).

## Déploiement automatique (GitHub Actions)
`.github/workflows/relay-cloudflare.yml` : à chaque push sur `main` qui touche `server/`, ou à la
main (Actions → « Relais Cloudflare » → Run workflow). Il lance les tests (Node, puis le Worker
sous `wrangler dev`), déploie, vérifie `/health` et écrit dans le résumé du job l'URL à mettre
dans le jeu.

Secrets du dépôt (Settings → Secrets and variables → Actions) :
- `CLOUDFLARE_API_TOKEN` : jeton créé avec le modèle « Edit Cloudflare Workers » ;
- `CLOUDFLARE_ACCOUNT_ID` : identifiant du compte (page d'accueil du tableau de bord).

Au premier déploiement, Cloudflare crée l'adresse `raidersgo-relay.<sous-domaine>.workers.dev`.
Si le compte n'a pas encore de sous-domaine `workers.dev`, ouvrir une fois **Workers & Pages**
dans le tableau de bord pour le choisir.

## Brancher le jeu
`data/balance.cfg`, section `[net]` : `url_prod="wss://raidersgo-relay.<sous-domaine>.workers.dev"`
(l'URL exacte est dans le résumé du job de déploiement).

## En local
```bash
cd server/cloudflare
npm ci
npm run dev        # ws://127.0.0.1:8799, santé sur http://127.0.0.1:8799/health
npm test           # lance wrangler dev (délais de grâce à 300 ms) et rejoue ../test/relay.test.js
npx wrangler deploy   # déploiement manuel (CLOUDFLARE_API_TOKEN et CLOUDFLARE_ACCOUNT_ID dans l'environnement)
```

## Réglages (`wrangler.toml`, section `[vars]`)
| Variable | Défaut | Rôle |
|---|---|---|
| `HOST_GRACE_MS` | 15000 | délai de reconnexion de l'hôte avant fermeture du salon |
| `GUEST_GRACE_MS` | 20000 | délai de reconnexion de l'invité avant son retrait |
| `IDLE_TIMEOUT_MS` | 30000 | connexion muette coupée après ce délai |
| `MAX_ROOMS` | 5000 | salons simultanés max |
| `LOG` | 0 | `1` = journal des salons (`npx wrangler tail`) |

## Coût
Durable Objects avec stockage SQLite : disponibles sur l'offre gratuite de Workers, dans ses
limites de requêtes et de durée d'exécution. Un objet reste actif tant que des joueurs sont
connectés : pour des tests et un petit public, l'offre gratuite suffit ; au-delà, l'offre Workers
Paid (5 $/mois) couvre largement le relais. Vérifier les tarifs à jour sur le site de Cloudflare.
