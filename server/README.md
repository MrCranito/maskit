# Serveur relais du coop en ligne — RaidersGo

Deux iPhone sur des réseaux différents (box, 4G) ne peuvent pas se connecter directement de façon
fiable (NAT). Ce petit serveur **Node.js + `ws`** sert de point de rendez-vous :

- il gère des **salons à code de 6 caractères** (sans I, L, O, 0, 1 pour éviter les confusions) ;
- il **relaie** les messages entre l'hôte et l'invité (il ne simule rien : c'est le jeu de
  l'**hôte** qui fait autorité sur la carte, l'IA, les dégâts et le butin) ;
- il vérifie la **version du protocole** (`PROTOCOL_VERSION`, à garder égale à
  `NetProtocol.VERSION` dans `scripts/net/net_protocol.gd`) ;
- il gère la **reconnexion** (jeton de reprise, messages gardés pendant la coupure),
  le **ping**, et **ferme le salon si l'hôte part** (immédiatement s'il quitte, après 15 s s'il
  est coupé) ; un invité coupé plus de 20 s est retiré du salon (considéré comme mort).

Mémoire seulement (pas de base de données) : un seul serveur suffit, ~1 Mo pour des centaines
de salons. Les salons expirent au bout de 6 h.

## Lancer en local (développement)

```bash
cd server
npm ci          # installe ws (une seule fois)
npm start       # écoute sur ws://127.0.0.1:8787
npm test        # tests du relais (codes, salons, reprise)
```

Dans le jeu, l'URL de développement est `[net] url_dev="ws://127.0.0.1:8787"` (`data/balance.cfg`).
Pour tester sur un iPhone avec le serveur sur ton ordinateur (même Wi-Fi), mets l'IP locale de
l'ordinateur : `url_dev="ws://192.168.1.20:8787"`.

Test d'intégration complet (serveur + deux jeux headless qui créent / rejoignent un salon, font un
raid, tirent, réaniment et s'extraient) : `tools/net_smoke_test.sh` (renvoie 0 si tout passe).

## Déployer en production (WSS obligatoire)

Sur iPhone, une app publiée doit utiliser **`wss://`** (TLS). Les hébergeurs ci-dessous
fournissent le TLS automatiquement : le serveur écoute en clair derrière eux, tu n'as aucun
certificat à gérer. Choisis-en **un seul**.

### Option A — Fly.io (recommandé : toujours allumé, proche de Paris, ~2 €/mois ou offre gratuite)

1. Crée un compte sur https://fly.io et installe l'outil : `curl -L https://fly.io/install.sh | sh`
2. Connecte-toi : `fly auth login`
3. Dans le dossier `server/` :
   ```bash
   cd server
   fly launch --copy-config --no-deploy   # garde fly.toml ; choisis un nom d'app libre si besoin
   fly deploy
   ```
4. Vérifie : `curl https://<nom-de-l-app>.fly.dev/health` doit répondre `{"ok":true,...}`.
5. L'URL du jeu est **`wss://<nom-de-l-app>.fly.dev`**.

`fly.toml` garde une machine allumée (`auto_stop_machines = "off"`) : les salons vivent en
mémoire, il ne faut pas que le serveur s'endorme pendant une partie.

### Option B — Render (gratuit, mais s'endort après 15 min sans connexion)

1. Pousse le dépôt sur GitHub, crée un compte sur https://render.com.
2. **New +** → **Blueprint** → choisis le dépôt : `server/render.yaml` est détecté
   (service Docker, dossier `server`, santé sur `/health`).
   Ou à la main : **New +** → **Web Service** → dépôt → *Root Directory* `server`,
   *Runtime* Docker.
3. L'URL du jeu est **`wss://raidersgo-relay.onrender.com`** (le nom affiché par Render).

Offre gratuite : le premier joueur qui ouvre un salon après une période d'inactivité attend
~30 à 50 s le réveil du serveur (le jeu affichera « Serveur injoignable » si c'est plus long que
6 s : réessayer). Pour des tests réguliers, prends l'offre payante la moins chère ou Fly.io.

### Option C — Railway

**New Project** → **Deploy from GitHub repo** → *Root Directory* `server` (le Dockerfile est
utilisé) → **Settings > Networking > Generate Domain**. URL : `wss://<domaine>.up.railway.app`.

### Option D — VPS (Ubuntu, avec ton nom de domaine)

```bash
sudo apt install -y docker.io caddy
cd server && sudo docker build -t raidersgo-relay . \
  && sudo docker run -d --restart=always -p 127.0.0.1:8787:8787 --name relay raidersgo-relay
# /etc/caddy/Caddyfile  (Caddy obtient le certificat TLS tout seul) :
#   relais.mondomaine.fr {
#       reverse_proxy 127.0.0.1:8787
#   }
sudo systemctl reload caddy
```
URL : `wss://relais.mondomaine.fr`.

## Brancher le jeu sur le serveur

Dans `data/balance.cfg`, section `[net]` :

```ini
url_prod="wss://raidersgo-relay.fly.dev"
```

Les exports de production (non debug) utilisent `url_prod` dès qu'elle est remplie. Pour
l'utiliser aussi depuis l'éditeur : `use_prod=true`. Pour un test ponctuel :
variable d'environnement `RAIDERSGO_NET_URL=wss://...` ou argument `--net-url=wss://...`.

Penser à changer `PROTOCOL_VERSION` (serveur) **et** `NetProtocol.VERSION` (jeu) ensemble si le
format des messages de contrôle change : les anciens clients reçoivent alors « Version différente
du serveur : mets le jeu à jour ».

## Variables d'environnement

| Variable | Défaut | Rôle |
|---|---|---|
| `PORT` | 8787 | port d'écoute (fourni par l'hébergeur) |
| `HOST` | 0.0.0.0 | interface |
| `HOST_GRACE_MS` | 15000 | délai de reconnexion de l'hôte avant fermeture du salon |
| `GUEST_GRACE_MS` | 20000 | délai de reconnexion de l'invité avant son retrait (= mort) |
| `MAX_ROOMS` | 5000 | salons simultanés max |
| `LOG` | — | `1` = journal des salons |

## Protocole (résumé)

- **Trames texte (JSON)** : `hello {v}` → `welcome` ou `error {code:"version"}` ;
  `create {name}` → `created {code, token}` ; `join {code, name}` → `joined {code, token, peer}`
  (erreurs `bad_code`, `not_found`, `full`) ; `resume {code, token}` → `resumed` ;
  `leave` ; `relay {d}` (messages du salon : infos des joueurs, carte, lancement) ;
  `ping {ts}` → `pong {ts}`. Notifications : `peer_joined`, `peer_lost {grace_ms}`, `peer_back`,
  `peer_left {reason}`, `room_closed {reason}`.
- **Trames binaires** : données de jeu (`scripts/net/net_protocol.gd`), relayées telles quelles.
  Paquet = suite de messages `[u8 type][u16 longueur][données]`, positions quantifiées au pixel
  sur 16 bits, angles sur 8/16 bits, PV sur 8 bits. État d'un joueur : 20 octets, 20 fois/s ;
  ennemis proches du coéquipier : 10 octets chacun, 15 fois/s ; événements (tirs, morts,
  portes, fouilles, gadgets…) regroupés en un paquet par image. ≈ 3 à 6 ko/s par joueur.
- Limites : 64 Kio par message, 300 messages/s par connexion (au-delà : coupure).

## Règles du coop (rappel des choix)

- Changement d'étage **commun** : prendre un escalier lance un compte à rebours de 3 s chez les
  deux (l'invité le demande à l'hôte), puis les deux changent d'étage ensemble.
- À 0 PV : **à terre** 15 s ; le coéquipier **réanime** en maintenant l'action 3 s à côté
  (35 % des PV). Pas relevé : mort (arsenal et butin perdus), puis **spectateur** du coéquipier.
- Extraction **individuelle** : chacun met à jour **son** profil avec **son** butin ; celui qui
  part avant regarde l'autre.
- Invité déconnecté plus de 20 s : considéré comme **mort**. Hôte déconnecté : fin du raid pour
  l'invité, qui **garde son arsenal** emporté mais **perd le butin** du raid.
- Difficulté à deux : PV des ennemis × `[net] coop_enemy_hp_mult` (1,6).
