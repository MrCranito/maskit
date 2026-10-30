# Playtest automatique (bot headless)

Outils de la campagne de playtest (rapport : `docs/playtest/<date>/RAPPORT.md`).

| Fichier | Rôle |
|---|---|
| `playtest_main.gd` + `playtest_bot.gd` | Bot joueur : joue un vrai raid (scène `Raid`, `Player` réel) et écrit un journal JSON |
| `run_campaign.py` | Orchestrateur reprenable (passes A, B, boss, duel), 2 parties en parallèle au plus |
| `drop_sim_main.gd` + `drop_sim.gd` | Volet 3 : taux de drop par simulation directe (`LootRoller` / `LootManager` réels) |
| `anim_audit_main.gd` + `anim_audit.gd` | Volet 4 : audit des planches d'animation des monstres + planches PNG par monde |
| `analyze.py` | Agrégats, CSV résumés et graphiques PNG à partir des journaux |
| `scripts/debug/playtest_probe.gd` | Sonde d'instrumentation du jeu, **désactivée par défaut** (seul le bot l'active) |
| `tests/test_playtest_bot.gd` | Test GUT : le bot joue un raid court (l'outil ne doit pas casser) |

## Le bot
- Aucune triche : mêmes PV, mêmes armes et chargeurs qu'un joueur. Il pilote le joueur par deux
  joysticks virtuels (déplacement ; visée + tir continu avec l'aide à la visée du mobile), fouille
  avec l'action « Fouiller » (immobile, interrompue par un coup), prend le butin comme « Tout
  prendre », se soigne avec les consommables du sac comme l'inventaire, lance son équipement,
  change d'arme selon la distance, se met à couvert, esquive les attaques télégraphiées (il lit
  la phase d'armement, ce que le joueur voit à l'écran), recule devant la mêlée, va à
  l'extraction et y canalise.
- Il ne voit que ce que voit le joueur : ennemis non masqués par le brouillard, en ligne de vue.
- Profils : `prudent`, `agressif` (descend les étages, cherche le combat), `fouilleur`.
- Arsenal par difficulté : Facile et Normal → débutant (P9, MP5, grenade) ; Difficile et Expert
  → moyen (M4A1, Glock 18, M24, grenade) ; Cauchemar → bien équipé (SCAR-H, M82, P90, C4).
- Accélération : `--fixed-fps 60` sans limite d'images (la physique avance de 1/60 s par image,
  aussi vite que le processeur le permet ; environ 9× le temps réel). `Engine.time_scale` n'est
  pas utilisé, pour ne pas changer le pas de la physique.
- Limites connues : il ne lit pas les zones au sol (tornades, flaques), ne contourne pas les
  ennemis par les toits ni n'utilise les cachettes ; il est plus faible qu'un bon joueur humain.

```bash
godot --headless --path . --fixed-fps 60 -s res://tools/playtest/playtest_main.gd -- \
  --mode=raid --map=perm_dust_creek --difficulty=1 --profile=prudent --seed=42 --out=/tmp/p.json
# --mode=boss (départ à l'entrée de l'arène), --mode=duel --enemy=fw_buffalo, --tier=equipe,
# --max-time=300 (s de jeu). Captures (sous xvfb, sans --headless) : --shots=DOSSIER --shot-every=5
```

## Campagne
```bash
python3 tools/playtest/run_campaign.py --root /tmp/campagne --pass A --godot $GODOT
python3 tools/playtest/run_campaign.py --root /tmp/campagne --pass B --godot $GODOT
python3 tools/playtest/run_campaign.py --root /tmp/campagne --pass boss --godot $GODOT
python3 tools/playtest/run_campaign.py --root /tmp/campagne --pass duel --godot $GODOT
godot --headless --path . -s res://tools/playtest/drop_sim_main.gd -- --out=/tmp/campagne/drops.json
godot --headless --path . -s res://tools/playtest/anim_audit_main.gd -- --out=/tmp/campagne/anim
python3 tools/playtest/analyze.py --root /tmp/campagne --drops /tmp/campagne/drops.json --out docs/playtest/<date>
```
Relancer une commande reprend où elle s'est arrêtée : les journaux déjà écrits sont gardés.
Chaque partie a son propre dossier de données Godot (`XDG_DATA_HOME`) : la sauvegarde du joueur
n'est jamais touchée.

## Journal d'une partie (JSON)
`seed`, `map`, `world`, `difficulty`, `profile`, `tier`, `arsenal`, `gadget`, `outcome`
(extraction / mort / temps / victoire), `killer`, `duration` (s de jeu), `hp_min`, `hp_end`,
`damage_taken` / `hits_taken` / `damage_dealt` / `kills` par type d'ennemi, `ttk` (s du premier
dégât à la mort, par type), `seen`, `elites` (rencontrées / tuées), `boss` (rencontre, phases,
PV restants, compétence du dernier coup), `items` (par source et rareté), `item_ids`,
`gold_estimate` (or au marchand du sac), `xp` (niveau de raider), `shots` (tirs par arme),
`gadgets_used`, `heals_used`, `dodges`, `containers_opened`, `corpses_searched`,
`stuck_enemies` (alertés immobiles 5 s), `unreachable_containers` (sans chemin depuis
l'arrivée), `bot_stuck`, `worst_frame_ms` / `avg_frame_ms` (temps d'image, voir ci-dessous),
`errors` / `warnings` (Godot).

Le temps d'image est mesuré en headless (sans rendu) : il reflète le coût de la logique (IA,
physique, scripts), pas le rendu d'un téléphone.
