# Playporter

> Document de reprise — récap complet des décisions prises pour démarrer le projet dans une session dédiée.
> (Ce n'est pas le transcript brut de la conversation, mais la synthèse structurée de tout ce qui a été décidé.)

---

## 🎯 Objectif

Créer une **app macOS native (SwiftUI)** qui fait pour **Google Play Console** ce que **Transporter** fait pour Apple :

> On dépose un fichier `.aab` sur l'app → elle **détecte automatiquement l'app concernée** (via le `applicationId` contenu dans l'AAB) → elle **upload sur le circuit « Test interne »** de la bonne app → notification « ✅ envoyé ».

**Pourquoi :** il n'existe aucun équivalent macOS clé-en-main de Transporter côté Google Play. Google n'a jamais sorti d'app desktop. Les seules solutions existantes sont CLI (fastlane `supply`, EAS Submit, Gradle Play Publisher) ou le glisser-déposer manuel dans le web de la Play Console.

## 📛 Nom retenu

**Playporter** (calque de « Transporter » côté Play).

---

## 🧭 Décisions clés

| Sujet | Décision | Raison |
|---|---|---|
| **Authentification** | **OAuth 2.0 « Se connecter avec Google » (PKCE)** — PAS de clé de service JSON | UX plus intuitive ; l'utilisateur se connecte en tant que personne et publie sur les apps auxquelles son compte Play a accès |
| **Type de client OAuth** | **Desktop app** | Gère le redirect loopback + PKCE automatiquement, pas de secret à protéger |
| **Build des apps** | En **local** (Gradle, dossiers `android/`) | AAB généré dans `android/app/build/outputs/bundle/release/` |
| **Autonomie de l'app** | **Zéro dépendance externe** : appels **directs à l'API Google Play** en HTTPS + parsing de l'AAB en Swift (pas de Ruby/fastlane, pas de Java/bundletool) | Rendre l'app vraiment distribuable |
| **Distribution macOS** | Notarisation via le **workflow déjà utilisé pour l'app Timer** (Apple Developer ID en poche) | — |
| **Circuit de publication ciblé** | **Test interne** (`internal`) | Besoin exprimé |
| **Cible OS** | **macOS 13+** | (à confirmer) |
| **Emplacement projet** | `~/projets/itinnove/playporter` | Séparé de `disquedur` |

## ⚙️ Ce que fait l'app (flux technique)

1. **Connexion Google** (OAuth PKCE, token stocké dans le **Trousseau** macOS).
2. **Zone de drop** → dépôt de `app-release.aab`.
3. **Lecture du package** dans l'AAB : `base/manifest/AndroidManifest.xml` (protobuf), extraction du `applicationId` — **sans Java/bundletool**.
4. **Upload API Play** : `edits.insert` → upload de l'AAB → assignation au track **internal** → `commit`.
5. **Notification native** « ✅ envoyé sur Test interne ».

---

## ☁️ Setup Google Cloud (à faire une fois, côté utilisateur)

1. **console.cloud.google.com** → créer un projet **« Playporter »**.
2. **APIs & Services → Bibliothèque** → activer **« Google Play Android Developer API »**.
3. **Écran de consentement OAuth** :
   - Type : **Externe**
   - Nom : *Playporter*, email de support, contact dev
   - **Scopes** → ajouter `https://www.googleapis.com/auth/androidpublisher` (scope **« sensible »**)
   - **Test users** → ajouter son email + ceux de l'équipe (jusqu'à 100)
   - Statut : **Test**
4. **Identifiants → Créer → ID client OAuth** → type **Application de bureau (Desktop app)** → récupérer le **Client ID** (`xxxxx.apps.googleusercontent.com`).
5. **Play Console → Configuration → Accès à l'API** → **lier le projet Google Cloud** Playporter.

➡️ **Valeur à fournir ensuite pour brancher l'auth : le `Client ID`.**

## 👥 Stratégie testeurs / passage grand public

- **Mode Test** (immédiat, choisi pour démarrer) : ajouter les **jusqu'à 100 testeurs manuellement** (email Google) dans *Test users*. On démarre avec **soi + l'équipe**.
- **Bascule Test → Production** = un **réglage dans Google Cloud Console**, **AUCUNE modif de l'app** (même Client ID, même code, même notarisation).
- **Prérequis pour passer public** (à anticiper) : **politique de confidentialité (URL)** + **domaine vérifié** + review Google de quelques jours (version **légère** de la vérif car scope « sensible », pas « restreint » → pas d'audit de sécurité payant).
- ⚠️ **Gotcha mode Test** : les **refresh tokens OAuth expirent au bout de 7 jours** → reconnexion hebdo des testeurs. Une fois **publié/vérifié**, tokens longue durée. (Aucune modif de code nécessaire.)
- **Plan** : passer public si on voit de l'intérêt (visiteurs sur le site).

## ✅ Prérequis déjà en place

- Compte **Google Developer** ✔️
- Compte **Apple Developer** ✔️ (notarisation déjà maîtrisée via l'app Timer)

---

## 📋 Prochaines étapes

- [ ] **Setup Google Cloud** (étapes ci-dessus) → récupérer le **Client ID**
- [ ] **Scaffolder le projet Xcode SwiftUI** Playporter (macOS 13+) dans ce dossier
- [ ] Implémenter : OAuth PKCE + stockage Trousseau
- [ ] Implémenter : parsing de l'AAB (extraction `applicationId` du manifeste protobuf)
- [ ] Implémenter : upload API Play (`edits.insert` → upload → track `internal` → `commit`)
- [ ] Zone de drop + notifications natives
- [ ] Notarisation (workflow Timer)
- [ ] (plus tard) Onboarding + passage écran de consentement en Production pour diffusion large

## 🔑 Valeurs de config (à remplir)

```
OAUTH_CLIENT_ID = "________.apps.googleusercontent.com"   # à récupérer après le setup Google Cloud
BUNDLE_ID (Playporter)   = "com.itinnove.playporter"      # à confirmer
MACOS_DEPLOYMENT_TARGET  = 13.0                            # à confirmer
```
