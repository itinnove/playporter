# Playporter

**Le « Transporter » de Google Play, pour macOS.** Glissez-déposez un `.aab`, il part
en **Test interne** sur Google Play Console — détection automatique de l'application,
connexion Google, upload via l'API officielle.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black) ![Swift](https://img.shields.io/badge/Swift-5-orange)

## Fonctionnalités

- 🎯 **Détection automatique** du package et de la version depuis l'AAB (sans Java/bundletool)
- 🔐 **Connexion Google** en OAuth 2.0 (PKCE), jeton dans le Trousseau macOS
- 🚀 **Upload API Play** : edit → bundle → canal `internal` → commit
- 🗂️ **File d'attente & historique** persistants, filtre par application
- 🖱️ **Glisser-déposer** sur toute la fenêtre + sélecteur de fichiers
- 📦 App **native autonome** — aucune dépendance externe à l'exécution

## Installation

Téléchargez le `.dmg` depuis les [releases](https://github.com/itinnove/playporter/releases)
et glissez Playporter dans Applications. L'app est signée Developer ID et notarisée Apple.

## Compilation depuis les sources

Prérequis : Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
# 1. Configurez vos identifiants OAuth (client Google « Desktop »)
cp Secrets.swift.example Sources/Secrets.swift
#   puis renseignez clientID / clientSecret dans Sources/Secrets.swift

# 2. Générez le projet et compilez
xcodegen generate
open Playporter.xcodeproj
```

`Sources/Secrets.swift` est **gitignoré** : il ne contient pas de secret partagé,
chaque installation utilise son propre client OAuth.

### Configuration Google Cloud

1. Activez la **Google Play Android Developer API** sur votre projet Google Cloud.
2. Écran de consentement OAuth (externe) avec le scope `androidpublisher`.
3. Créez un **ID client OAuth de type « Application de bureau »** → reportez le
   `clientID` / `clientSecret` dans `Sources/Secrets.swift`.
4. Play Console → **Accès à l'API** → liez votre projet Cloud.

## Packaging & distribution

```bash
./scripts/package.sh   # build Release → signature Developer ID → notarisation → .zip
./scripts/make_dmg.sh  # .dmg (glisser-vers-Applications) notarisé
```

Ces scripts attendent un certificat « Developer ID Application » et un profil
`notarytool` nommé `itinnove` (voir `xcrun notarytool store-credentials`).

## Licence

MIT — voir [LICENSE](LICENSE).
