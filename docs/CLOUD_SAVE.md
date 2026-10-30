# Sauvegarde cloud et comptes (Supabase)

Projet Supabase : `ybtbbshplmjbebuaxrgy` (région eu-west-3). URL et clef publique dans
`data/cloud.cfg`. Schéma : `supabase/migrations/20261030_cloud_save.sql`.

## Principe
- **Local d'abord.** `SaveManager` écrit toujours `user://save.json`. L'autoload `CloudSync`
  (`scripts/net/cloud_sync.gd`) pousse ce fichier au serveur ~2 s après chaque écriture
  (regroupement), quand l'app passe en arrière-plan, et le récupère à la connexion.
- **Compte invité automatique.** Au premier lancement, connexion anonyme Supabase ; le jeton
  est gardé dans `user://cloud_session.json` (chiffré avec l'identifiant de l'appareil). Le
  joueur ne voit rien. La liaison Apple / Google (retrouver son compte sur un autre téléphone)
  est l'étape suivante.
- **Version.** `SaveManager.data["_cloud"] = {version, dirty}`. `version` = version serveur de
  la dernière synchro, `dirty` = modifications locales non envoyées (persisté dès la première
  écriture). La fonction `push_save` refuse un envoi dont la version de base n'est plus la
  sienne → **conflit** (joué sur deux appareils), tranché par le joueur dans
  `CloudConflictPanel` (« Garder ce téléphone » / « Garder le cloud »).
- **Décision à la connexion** (`CloudSync.decide`, testée dans `tests/test_cloud_sync.gd`) :

| Local | Serveur | Action |
|---|---|---|
| quoi que ce soit | pas de sauvegarde | pousser |
| version 0 (jamais synchronisé) | sauvegarde | prendre le cloud |
| même version, propre | — | rien |
| même version, modifié | — | pousser |
| plus ancien, propre | plus récent | prendre le cloud |
| plus ancien, modifié | plus récent | **conflit** |
| plus récent | plus ancien | pousser |

- **Le client ne crédite jamais de gemmes achetées.** Tables `purchases`, `wallets`,
  `entitlements` : lecture seule pour le joueur, écriture par le serveur (Edge Function de
  validation des reçus Apple/Google, à venir ; remplace `Store.SIMULATED`). `pull_state`
  renvoie `gems_granted` et `entitlements` ; `CloudSync.gems_granted` / `entitlements` les
  exposent.

## Serveur (SQL)
- `player_saves` (une ligne par joueur : `save` jsonb, `version`, `device`, `client_ver`).
- `push_save(p_save, p_base_version, p_device, p_client_ver)` → `{ok, version}` ou
  `{ok:false, reason:'conflict', version, save, updated_at, device}`. Limite 1 Mo.
- `pull_state()` → `{save:{save, version, updated_at, device}|null, gems_granted, entitlements}`.
- RLS sur toutes les tables : `auth.uid() = user_id`. Les fonctions sont `security invoker`.

## Réglages Supabase à faire à la main (console)
- Authentication → Sign In / Providers → **Allow anonymous sign-ins : ON** (sinon le jeu
  reste en « Hors ligne » et le journal affiche l'avertissement CloudSync).
- Plus tard : fournisseurs Apple et Google pour la liaison de compte.

## Interface
- Lobby, pied de page : point coloré + « Sauvegarde cloud à jour » / « Synchronisation… » /
  « Hors ligne : sauvegarde locale » / « Conflit de sauvegarde ».
- Options → section « Sauvegarde cloud » : état, identifiant court du compte invité,
  bouton **Synchroniser**.
- Conflit : fenêtre « Deux sauvegardes » (deux cartes : niveau, gemmes, or, armes, raids, date).

## Tests et headless
`CloudSync.enabled()` est faux en headless (tests GUT, CI) : aucun appel réseau. Pour couper
le cloud dans l'éditeur : `enabled=false` dans `data/cloud.cfg`.
