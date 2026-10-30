# Sauvegarde cloud et comptes (Supabase)

Projet Supabase : `ybtbbshplmjbebuaxrgy` (région eu-west-3). URL et clef publique dans
`data/cloud.cfg`. Schéma : `supabase/migrations/20261030_cloud_save.sql`.

## Principe
- **Local d'abord.** `SaveManager` écrit toujours `user://save.json`. L'autoload `CloudSync`
  (`scripts/net/cloud_sync.gd`) pousse ce fichier au serveur ~2 s après chaque écriture
  (regroupement), quand l'app passe en arrière-plan, et le récupère à la connexion.
- **Compte invité automatique.** Au premier lancement, connexion anonyme Supabase ; le jeton
  est gardé dans `user://cloud_session.json` (chiffré avec l'identifiant de l'appareil). Le
  joueur ne voit rien.
- **Liaison Apple / Google** (Options → « Lier mon compte », `CloudSync.link_account`,
  `scripts/net/account_link.gd`) : l'identité est rattachée au compte invité (toute la
  progression suit). Si l'identité est déjà rattachée à un autre compte (nouveau téléphone),
  on bascule sur ce compte et la sauvegarde locale est réconciliée (conflit si les deux ont
  progressé). Jetons : plugins natifs sur mobile, navigateur + PKCE sur PC (voir plus bas).
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

## Achats vérifiés par le serveur (étape 3)
- Le jeu n'accorde plus rien tout seul quand le cloud est joignable : `Store.purchase_pack` /
  `purchase_bundle` → `CloudSync.purchase(store, product_id, reçu)` → Edge Function
  **`verify_purchase`** → vérification du reçu auprès d'Apple (App Store Server API, JWS signé,
  chaîne Apple Root CA G3) ou de Google (Android Publisher, acquittement) → `grant_purchase`
  (idempotent par transaction) → réponse → `Store.fulfill_pack` / `fulfill_bundle` crédite
  localement. Catalogue serveur `products` = seule source des gemmes / droits ; premier pack de
  gemmes ×2 côté serveur.
- Tant que les plugins de paiement natifs ne sont pas branchés (`Store.native_receipt()` vide),
  le reçu est `"simulated"` : accepté seulement si le secret Edge Function
  **`ALLOW_SIMULATED_PURCHASES`** = `true` (projet de test uniquement). Sans cloud (tests,
  headless) : crédit local immédiat, comme avant.
- **Restaurer mes achats** (Options) : `CloudSync.restore_purchases()` relit `entitlements`
  (`bundle_<id>`, plus tard le pass) et ré-accorde ce qui manque au profil.
- **Supprimer mon compte** (Options, obligatoire Apple/Google) : Edge Function
  **`delete_account`** (archive anonymisée des achats puis suppression de l'utilisateur →
  cascade), puis profil neuf en local et nouveau compte invité. Page publique :
  `docs/SUPPRESSION_COMPTE.md` (à référencer dans la fiche Play).
- Conformité stores : voir la section « Conformité » plus bas.

## Serveur (SQL)
- `player_saves` (une ligne par joueur : `save` jsonb, `version`, `device`, `client_ver`).
- `push_save(p_save, p_base_version, p_device, p_client_ver)` → `{ok, version}` ou
  `{ok:false, reason:'conflict', version, save, updated_at, device}`. Limite 1 Mo.
- `pull_state()` → `{save:{save, version, updated_at, device}|null, gems_granted, entitlements}`.
- RLS sur toutes les tables : `auth.uid() = user_id`. Les fonctions sont `security invoker`.

- `products` (catalogue), `purchases_archive`, fonctions `grant_purchase` (service role) ;
  Edge Functions `verify_purchase`, `delete_account` (`supabase/functions/`).

## Réglages Supabase à faire à la main (console)
- Authentication → Sign In / Providers → **Allow anonymous sign-ins : ON** (fait).
- Authentication → Sign In / Providers → **Allow manual linking : ON** (sinon la liaison crée
  une bascule de compte au lieu d'un rattachement).
- Authentication → URL Configuration → Redirect URLs : `http://127.0.0.1:48791/cb` (liaison
  depuis PC / éditeur).
- Providers **Apple** (Services ID, Team ID, Key ID, clé .p8) et **Google** (client ID / secret
  Web ; sur Android, ajouter le client Android avec le SHA-1 de la clé de signature). Le client
  Web Google va aussi dans `data/cloud.cfg` `[auth] google_web_client_id`.
- Edge Functions → Secrets : `ALLOW_SIMULATED_PURCHASES=true` (test), puis pour la prod :
  `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APPLE_BUNDLE_ID`,
  `APPLE_ALLOW_SANDBOX` (TestFlight), `GOOGLE_SERVICE_ACCOUNT_JSON`, `GOOGLE_PACKAGE_NAME`,
  `GOOGLE_ALLOW_TEST`, `FIRST_PURCHASE_MULTIPLIER` (défaut 2).

## Plugins natifs (mobile)
- Android, connexion Google : « Godot Google Sign-In » (NiqueWrld, Credential Manager,
  singleton `GodotGoogleSignIn`, `initialize(web_client_id)` puis `signInWithAccountChooser()`,
  signal `sign_in_success(id_token, …)`). Gradle build requis.
- iOS, Sign in with Apple : « Godot Apple Plugins » (migueldeicaza, `ASAuthorizationController`,
  `signin_with_scopes`, signal `authorization_completed(credential)`) + entitlement
  `com.apple.developer.applesignin`. `AccountLink` lit le jeton sous `identity_token` /
  `identityToken`.
- Paiement : Google Play Billing et StoreKit 2, à brancher dans `Store.native_receipt()`
  (purchaseToken / transaction id) et pour les prix affichés (`ProductDetails` /
  `Product.displayPrice`, obligatoires à la place de `balance.cfg`).

## Conformité App Store / Google Play (vérifiée le 30/10/2026)
- Monnaie virtuelle : les gemmes n'expirent jamais ✔. Achats uniquement par StoreKit / Play
  Billing, vérifiés serveur ✔ (le mode simulé ne doit jamais partir en prod).
- Loot boxes : les coffres ne sont pas vendus et leurs taux sont affichés ✔.
- Connexion tierce (Google) ⇒ Sign in with Apple obligatoire sur iOS ✔.
- Suppression de compte dans l'app, y compris comptes invités ✔ + page web (fiche Play).
- Restauration des achats ✔. Prix affichés = prix du store (à faire avec les plugins).
- À faire au moment de publier : politique de confidentialité en ligne, formulaires
  « Data safety » / « App Privacy », révocation des jetons Apple à la suppression.

## Interface
- Lobby, pied de page : point coloré + « Sauvegarde cloud à jour » / « Synchronisation… » /
  « Hors ligne : sauvegarde locale » / « Conflit de sauvegarde ».
- Options → section « Sauvegarde cloud » : état, identifiant court du compte invité,
  bouton **Synchroniser**.
- Conflit : fenêtre « Deux sauvegardes » (deux cartes : niveau, gemmes, or, armes, raids, date).

## Tests et headless
`CloudSync.enabled()` est faux en headless (tests GUT, CI) : aucun appel réseau. Pour couper
le cloud dans l'éditeur : `enabled=false` dans `data/cloud.cfg`.
