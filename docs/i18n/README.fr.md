# 🌿 Pixel Terrarium

> Un petit terrarium cosy en pixel art qui vit paisiblement dans la barre de menus de votre Mac.

[English](../../README.md#english) | [简体中文](../../README.md#简体中文) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | **Français**

<p align="center">
  <img src="../assets/itch_cover_630x500.png" alt="Pixel Terrarium Cover" width="520" />
</p>

### 📸 Captures d'écran

| 🌿 Prairie Humide (Lush Meadow) | 🏜️ Désert Ensoleillé (Sunlit Desert) |
| :---: | :---: |
| <img src="../assets/screenshot_meadow.png" alt="Lush Meadow" width="380" /> | <img src="../assets/screenshot_sand.png" alt="Sunlit Desert" width="380" /> |
| **🌴 Forêt Tropicale (Tropical Rainforest)** | **🐟 Aquarium Cristallin (Crystal Aquatic)** |
| <img src="../assets/screenshot_rainforest.png" alt="Tropical Rainforest" width="380" /> | <img src="../assets/screenshot_aquatic.png" alt="Crystal Aquatic" width="380" /> |

---

### ✨ Fonctionnalités clés

- **4 Biomes distincts (jusqu'à 9 terrariums)** : Commencez avec un terrarium **Prairie** gratuit et débloquez **Désert Ensoleillé**, **Forêt Tropicale** et **Aquarium Cristallin**, avec **Éco-Résonance** inter-bacs.
- **52 Espèces à collectionner** :
  - **21 Plantes** : Mousse, fougères, champignons lumineux, succulentes, orchidées, boules de mousse marimo, nénuphars, etc.
  - **25 Créatures à adopter** : Rainettes, escargots, coccinelles, geckos léopards, caméléons, néons, crevettes cristal, etc. (avec stockage sûr selon la chaîne alimentaire et surnoms personnalisés).
  - **6 Visiteurs aériens** : Lucioles, papillons de lune, libellules et autres visiteurs rares apparaissant naturellement selon l'habitat.
- **Soins quotidiens et complicité** : Vaporisation/oxygénation, nourrissage, équipements thermiques (lampe chauffante, ventilateur, chauffage d'aquarium), 20 décors déplaçables, 5 cadres et caresses jusqu'au **niveau d'affinité Lv.5**.
- **Expérience native barre de menus** : Icône dynamique à 6 états, lumière d'aube/crépuscule, jusqu'à 8 heures de simulation hors ligne, Mode Sommeil et export de **captures pixel art 4x sans perte**.
- **8 langues intégrées** : Français, English, 简体中文, 繁體中文, 日本語, 한국어, Español et Deutsch.

### 💻 Installation (macOS 13.0+)

1. Téléchargez le dernier `.dmg` sur [GitHub Releases](https://github.com/jampsn/TerrariumMenuBar/releases) ou [itch.io](https://jamplus.itch.io/pixel-terrarium).
2. Glissez `TerrariumMenuBar.app` dans `/Applications`.
3. **Note de premier lancement (app non signée)** : S'agissant d'un projet indépendant gratuit sans certificat Apple Developer pour le moment, macOS Gatekeeper peut afficher un avertissement.
   - **Option A** : Clic droit sur `TerrariumMenuBar.app` → **Ouvrir** → confirmer **Ouvrir**.
   - **Option B** : Exécutez dans le Terminal :
     ```bash
     xattr -cr /Applications/TerrariumMenuBar.app
     ```

### 🛠️ Compiler depuis les sources

Nécessite **macOS 13.0+** et **Swift 5.9+** :

```bash
./build_app.sh
```

### 🛠️ Développement & transparence IA

Conçu, développé et équilibré de manière indépendante par **jam**. Des outils d'IA ont été utilisés en assistance pour la structure du code et l'exploration visuelle/couverture ; chaque mécanique, animation et interaction a été vérifiée et affinée manuellement.

### ❤️ Soutenir le projet

Pixel Terrarium est **100 % gratuit et open source**. Si ce petit monde apporte du calme à votre bureau, vous pouvez soutenir les futures mises à jour (et aider à financer le certificat Apple Developer) :

- 🎮 **itch.io (Pay What You Want)** : [https://jamplus.itch.io/pixel-terrarium](https://jamplus.itch.io/pixel-terrarium)

### 📄 Licence

- **Code source (`Sources/**/*.swift`, scripts)** : [Licence MIT](../../LICENSE)
- **Ressources graphiques (`Sources/TerrariumMenuBar/Resources/Pixel/`, `AppIcon.icns`, couvertures)** : **CC BY-NC-SA 4.0** (Usage non commercial). Voir [LICENSE](../../LICENSE).
