# RaidersGo — Plan : ce qu'il reste à faire et à ajouter (comptes, cloud, achats, stores)

État au 30/10/2026 : PR #22 (`feature/cloud-save`) prête à être validée. Tout ce qui suit est
**à ta charge** (consoles, comptes, secrets, plugins) ou **à me demander** (code marqué 🤖).

## 0. Tout de suite (10 min)
1. Relire et fusionner la **PR #22**. L'APK Android se reconstruit tout seul.
2. Console Supabase → Authentication → Sign In / Providers :
   - **Allow anonymous sign-ins : ON** (fait).
   - **Allow manual linking : ON** (sinon « Lier mon compte » bascule de compte au lieu de rattacher).
3. Console Supabase → Authentication → URL Configuration → **Redirect URLs** : ajouter
   `http://127.0.0.1:48791/cb` (liaison de compte depuis PC / éditeur).
4. Console Supabase → Edge Functions → Secrets : **`ALLOW_SIMULATED_PURCHASES` = `true`**
   (permet de tester les achats de bout en bout sans plugins de paiement). **À supprimer avant
   toute version store.**
5. Tester dans l'éditeur : lobby → « Sauvegarde cloud à jour » ; Options → Synchroniser ;
   Boutique → un pack de gemmes (les gemmes arrivent au retour du serveur) ; Options →
   Supprimer mon compte → profil neuf. Dans Supabase, Table Editor → `player_saves`,
   `purchases`, `wallets`.

## 1. Comptes développeur (prérequis à tout le reste)
- **Apple Developer Program** (99 $/an) : https://developer.apple.com/programs/
- **Google Play Console** (25 $ une fois) : https://play.google.com/console/
- **Google Cloud Console** (gratuit) : projet pour OAuth (connexion Google) + API Android Publisher.
- Identifiants à garder sous la main : bundle id iOS = `com.mrcranito.raidersgo` (à créer dans
  Apple Developer → Identifiers, avec la capacité **Sign in with Apple** et **In-App Purchase**),
  package Android = `com.mrcranito.raidersgo`.

## 2. Connexion Google (Android + liaison depuis PC)
Google Cloud Console → APIs & Services → Credentials :
1. Écran de consentement OAuth (nom RaidersGo, e-mail de contact, logo), publié.
2. **Client OAuth « Web »** → client ID + secret → Supabase → Authentication → Providers →
   **Google** (Client ID, Client Secret). Ce même client ID (Web) va dans
   `data/cloud.cfg` → `[auth] google_web_client_id` (le plugin Android en a besoin).
3. **Client OAuth « Android »** : package `com.mrcranito.raidersgo` + **SHA-1** de la clé de
   signature (debug ET release : `keytool -list -v -keystore <clé> -alias <alias>`).
4. Dans Supabase → Providers → Google, ajouter le client ID Android dans « Authorized Client IDs ».
5. 🤖 Plugin Android « Godot Google Sign-In » (github.com/NiqueWrld/GodotGoogleSignIn) : dossier
   `addons/GodotGoogleSignIn` + **Gradle build** activé dans l'export Android (+ Android build
   template). Le code (`AccountLink`) est déjà prêt ; dis-moi quand les identifiants existent.

## 3. Sign in with Apple (iOS, obligatoire dès qu'il y a Google)
Apple Developer :
1. Identifiers → App ID `com.mrcranito.raidersgo` → capacité **Sign in with Apple**.
2. Identifiers → **Services ID** (ex. `com.mrcranito.raidersgo.signin`) → Sign in with Apple
   configuré avec le domaine `ybtbbshplmjbebuaxrgy.supabase.co` et le Return URL
   `https://ybtbbshplmjbebuaxrgy.supabase.co/auth/v1/callback`.
3. Keys → nouvelle clé **Sign in with Apple** → télécharger le `.p8` (une seule fois !),
   noter **Key ID** et **Team ID**.
4. Supabase → Providers → **Apple** : Services ID (client ID), Team ID, Key ID, contenu du `.p8`.
   Dans « Authorized Client IDs », ajouter aussi le bundle id `com.mrcranito.raidersgo`
   (connexion native depuis l'app).
5. Export iOS Godot → entitlement `com.apple.developer.applesignin` = `Default`.
6. 🤖 Plugin « Godot Apple Plugins » (migueldeicaza) à ajouter au projet ; `AccountLink` lit déjà
   le jeton d'identité. Prévoir une passe de test sur un vrai iPhone (je ne peux pas lancer iOS).

## 4. Paiements intégrés (obligatoire pour publier : plus de paiement simulé)
### Produits à créer (mêmes identifiants des deux côtés, = catalogue serveur `products`)
| Identifiant | Type | Contenu | Prix indicatif |
|---|---|---|---|
| `gems_80` | consommable | 80 gemmes | 0,99 € |
| `gems_450` | consommable | 450 gemmes | 4,99 € |
| `gems_1000` | consommable | 1 000 gemmes | 9,99 € |
| `gems_2200` | consommable | 2 200 gemmes | 19,99 € |
| `bundle_recrue` | consommable* | skin GIGN + 450 gemmes (une fois) | 4,99 € |
| `bundle_commando` | consommable* | Spetsnaz + AK-47 Tigre | 9,99 € |
| `bundle_or_massif` | consommable* | SAS + Deagle Or + SCAR-H Or + 500 gemmes | 19,99 € |

\* déclarés consommables côté stores (le serveur garde le droit `bundle_<id>` et empêche le
double achat des packs « une fois »).

### App Store Connect
1. Créer l'app (bundle id), fiche, **In-App Purchases** ci-dessus, accord « Paid Apps » signé
   (Agreements, Tax, and Banking) sinon les achats ne se chargent pas.
2. Users and Access → Integrations → **In-App Purchase** → nouvelle clé → `.p8`, **Key ID**,
   **Issuer ID**.
3. Secrets Supabase (Edge Functions) : `APPLE_ISSUER_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`
   (contenu du .p8), `APPLE_BUNDLE_ID=com.mrcranito.raidersgo`, `APPLE_ALLOW_SANDBOX=true`
   pendant TestFlight (puis `false`).
4. Comptes **Sandbox testers** (App Store Connect → Users and Access → Sandbox) pour tester.

### Google Play Console
1. Créer l'app, fiche, **Produits intégrés** ci-dessus (actifs), profil de paiement marchand.
2. Google Cloud → IAM → **compte de service** → clé JSON ; Play Console → Users and
   permissions → inviter l'e-mail du compte de service avec « Afficher les données financières »
   + « Gérer les commandes ».
3. Secrets Supabase : `GOOGLE_SERVICE_ACCOUNT_JSON` (le JSON entier),
   `GOOGLE_PACKAGE_NAME=com.mrcranito.raidersgo`, `GOOGLE_ALLOW_TEST=true` pendant les tests.
4. **Testeurs de licence** (Play Console → Setup → License testing) pour acheter sans payer.
5. Publier au moins en **test interne** : les achats ne fonctionnent qu'avec une version
   signée par Play et installée depuis le Play Store.

### Côté jeu 🤖 (à me demander quand les produits existent)
- Android : plugin **Google Play Billing** (plugin officiel Godot `GodotGooglePlayBilling`) :
  `queryProductDetails` → prix affichés, `purchase` → `purchaseToken` → serveur →
  `consumePurchase`.
- iOS : plugin **StoreKit 2** (godot-ios-plugins « inappstore » ou Godot Apple Plugins) :
  `Product.displayPrice` → prix affichés, `purchase` → `transaction.id` → serveur → `finish`.
- Branchement déjà prévu : `Store.native_receipt()`, `Store.packs()` (prix), badge « Paiement
  simulé » retiré automatiquement quand un plugin est présent.
- Secret `ALLOW_SIMULATED_PURCHASES` supprimé, `APPLE_ALLOW_SANDBOX` / `GOOGLE_ALLOW_TEST` à
  `false` pour la prod.

## 5. Conformité et documents à publier
1. **Politique de confidentialité** en ligne (URL demandée par les deux stores). Contenu
   minimal : identifiant de compte (anonyme ou Apple/Google : e-mail éventuel), modèle
   d'appareil, sauvegarde de jeu, historique d'achats (justificatifs anonymisés conservés
   10 ans), hébergement Supabase (UE, Paris), suppression possible dans l'app. 🤖 Je peux
   la rédiger ; à héberger sur GitHub Pages (dossier `docs/`).
2. **Page de suppression de compte** : `docs/SUPPRESSION_COMPTE.md` existe → l'exposer via
   GitHub Pages et mettre l'URL dans Play Console → App content → Data deletion.
3. **Formulaires** : Play Console « Data safety » et App Store Connect « App Privacy »
   (données : identifiants, achats, contenu utilisateur = sauvegarde ; pas de pub, pas de
   tracking).
4. **Classification d'âge** (IARC sur Play, questionnaire Apple) : violence stylisée, achats
   intégrés.
5. 🤖 **Révocation des jetons Apple** à la suppression de compte (exigé par Apple) : à ajouter
   dans `delete_account` dès que la clé Sign in with Apple existe (même `.p8`).
6. 🤖 **Prix depuis les stores** à la place de `balance.cfg` (vient avec les plugins).
7. Optionnel : **page web de liaison/déconnexion** si un jour le jeu propose une connexion
   e-mail (non prévu).

## 6. Build et signature
- Android : **clé de signature release** (keystore) → secrets GitHub du workflow « Android
  APK » (procédure dans le fichier de build) ; sans elle, l'APK reste une version de test non
  publiable. Le **SHA-1 de cette clé** sert aussi à Google (section 2.3). Pour le Play Store,
  passer l'export en **AAB** (Gradle build, déjà requis par les plugins).
- iOS : certificats + profils de provisioning (capabilités Sign in with Apple, In-App
  Purchase), export Xcode, TestFlight.

## 7. Supabase : exploitation
- **Sauvegardes** : plan gratuit = pas de sauvegarde quotidienne ; passer au plan **Pro**
  (25 $/mois) avant le lancement (sauvegardes, pas de mise en pause après 7 jours d'inactivité,
  quotas Auth/Edge plus larges).
- **Sécurité** : Dashboard → Advisors (0 alerte aujourd'hui) à revérifier après chaque migration ;
  ne jamais mettre la **service role key** dans le jeu ou GitHub (seule la clé publique
  `sb_publishable_…` est dans `data/cloud.cfg`).
- **Secrets Edge Functions** : voir sections 4 ; `FIRST_PURCHASE_MULTIPLIER` (défaut 2).
- **Nettoyage** (🤖 plus tard) : purge des comptes invités jamais liés et inactifs depuis
  12 mois (fonction planifiée).

## 8. Ordre conseillé
1. §0 (aujourd'hui) → 2. §1 comptes → 3. §2 Google + §3 Apple (connexion) → 4. je branche les
plugins de connexion, test sur APK + iPhone → 5. §4 produits + secrets → 6. je branche les
plugins de paiement, test sandbox / testeurs de licence → 7. §5 documents + §6 signature →
8. test interne Play / TestFlight → 9. soumission.
