# Dust & Dollars 🤠💰

Prototype jouable d'un petit jeu d'arcade **2D en vue isométrique**, thème
**western cartoon** : braque une banque fictive, évite les gardes, ouvre le
coffre, ramasse le butin et file vers la sortie. (Rendu isométrique 2D : la
simulation reste cartésienne, seul l'affichage est projeté — aucune 3D.) **Jouable au navigateur** (desktop et
mobile), développé avec **Godot 4** en **GDScript** uniquement.

> Le concept complet et les contraintes sont figés dans [`CLAUDE.md`](CLAUDE.md).

## Ouvrir le projet dans Godot 4

1. Installer **Godot 4.x** (build standard, pas .NET requis — projet 100 % GDScript).
2. Lancer Godot → **Import** → sélectionner le fichier `project.godot` à la racine.
3. Ouvrir le projet.

## Lancer le jeu

- Dans l'éditeur, appuyer sur **F5** (Run Project).
- La scène principale est `scenes/Boot.tscn` (déjà configurée). Elle affiche un
  splash puis le **menu principal** → bouton **Jouer le braquage**.


## Réglages

Le menu principal contient maintenant un écran **Réglages** :

- activation / désactivation de l'audio ;
- volume des effets sonores synthétisés ;
- taille des contrôles tactiles pour améliorer la jouabilité sur téléphone.

Ces préférences sont sauvegardées dans `user://save.json` avec le reste de la progression.

## Contrôles

### Desktop (clavier)
| Action          | Touches                          |
|-----------------|----------------------------------|
| Se déplacer     | **WASD** ou **ZQSD** ou flèches  |
| Interagir / coffre | **E** (maintenir près du coffre) |
| Pause           | **Échap**                        |

### Mobile (navigateur tactile)
- **Joystick virtuel** : toucher/glisser dans la moitié **gauche** de l'écran.
- **Bouton E** : en bas à **droite** (maintenir pour ouvrir le coffre).

> L'émulation tactile à la souris est activée : sur desktop, on peut aussi tester
> le joystick et le bouton E à la souris.

## Boucle de jeu

0. **Ville** : on arrive dans le village western, on rejoint la **banque** à
   pied (dirige-toi vers la porte « BANQUE ») → le braquage démarre.
1. Récupère du butin (3 sacs **$**).
2. Ouvre le **coffre** (reste à côté, maintiens **E** → barre de progression).
3. Surveille la **jauge d'alarme** : les gardes qui te voient la font monter.
   À **100**, alerte générale → tous les gardes te poursuivent et **tirent**.
4. Combat au **six-coups** : vise au **clic**, **6 balles** puis **rechargement**
   (R / bouton RECH). Une balle abat un garde ; les gardes en alerte ripostent.
5. Atteins la **zone de sortie verte**.

- ✅ **Réussite** : sortir avec **au moins un butin**.
- ❌ **Échec** : tomber à **0 PV** (balles / contact d'un garde en alerte).

À la fin : **écran de résultat** (butin, argent gagné, totaux). La progression est
sauvegardée dans `user://save.json` (`total_money`, `missions_completed`).

## Exporter vers le web (HTML5 / WebAssembly / WebGL)

1. Dans Godot : **Project → Export…**.
2. **Add… → Web**. (Au premier export, Godot propose de télécharger les
   *export templates* — accepter.)
3. Vérifier que le renderer est **GL Compatibility** (déjà réglé dans
   `project.godot`, idéal pour WebGL et mobile).
4. **Export Project** → choisir un dossier (ex. `build/`) et nommer le fichier
   `index.html`.
5. Servir le dossier via **HTTP** (les jeux web Godot nécessitent les en-têtes
   COOP/COEP et ne fonctionnent pas en `file://`). Exemple rapide :
   ```bash
   cd build
   python3 -m http.server 8080
   # puis ouvrir http://localhost:8080/index.html
   ```

## 📱 Tester depuis ton téléphone (déploiement automatique)

Un workflow GitHub Actions (`.github/workflows/deploy-web.yml`) **construit l'export
Web et le publie sur GitHub Pages** à chaque push. Tu obtiens une URL publique à
ouvrir directement dans le navigateur de ton téléphone.

**Étape unique à faire une fois** sur GitHub (après le 1er run réussi du
workflow, qui crée la branche `gh-pages`) :
`Settings → Pages → Build and deployment → Source = **Deploy from a branch** →
Branch = **gh-pages** / **/(root)** → Save`.

Ensuite, à chaque push (ou via `Actions → Build & Deploy Web → Run workflow`), le
build est régénéré et poussé sur `gh-pages`, et Pages se met à jour. L'URL est :

```
https://sebadiaz.github.io/cowboys/
```

> Pourquoi cette méthode : le workflow **pousse le build sur la branche
> `gh-pages`** avec le token intégré, au lieu de passer par l'« environnement
> github-pages ». Ça évite les *règles de protection d'environnement* qui
> bloquent les déploiements depuis une branche non-défaut.

> Détails techniques : l'export désactive le *thread support* Godot
> (`variant/thread_support=false`) pour fonctionner sur GitHub Pages, qui n'envoie
> pas les en-têtes COOP/COEP requis par SharedArrayBuffer. Le renderer **GL
> Compatibility** (WebGL2) assure la compatibilité mobile. Contrôles tactiles
> intégrés (joystick + bouton E).
>
> Si le job *deploy* est bloqué par une protection d'environnement, autorise la
> branche dans `Settings → Environments → github-pages`, ou définis cette branche
> comme branche par défaut.

## Assets graphiques

Les décors sont fournis sous forme de **planches PNG** (atlas) découpées par
**régions d'atlas** sur des `Sprite2D` — pas de fichiers individuels par objet.

**Où placer les PNG :** `assets/source_sheets/` (planches 1254 × 1254)
- `bank_props_sheet.png` — **bâtiment** : sols, murs, comptoirs « BANK », tapis, portes
- `bank_interior_sheet.png` — **objets** : porte de coffre, coffre, bureau, chaise, barils, caisses, sacs `$`
- `western_exterior_sheet.png` — **extérieurs** : sable, barrières, cactus, chariot, façades

> Le contenu ne suit pas le nom du fichier (planches « croisées ») — voir le
> tableau dans [`assets/ASSET_INTEGRATION.md`](assets/ASSET_INTEGRATION.md).

**Comment c'est intégré :** chaque objet a une scène réutilisable dans
`scenes/props/` (ex. `SafeProp.tscn`, `BankCounter.tscn`, `BarrelProp.tscn`…) :
`Node2D` + `Sprite2D` (texture + `region_rect` d'atlas) + `CollisionShape2D` pour
les objets bloquants. La carte complète des régions est dans
[`assets/ASSET_INTEGRATION.md`](assets/ASSET_INTEGRATION.md).

**Lancer la scène de démo `BankVisualTest` :**
1. Ouvre `scenes/levels/BankVisualTest.tscn` dans Godot.
2. Appuie sur **F6** (Run Current Scene).
3. Tu vois une banque western 2D/2.5D composée des décors (sol, murs, comptoirs,
   coffre, butin, bureau, barils, caisses, tapis, sortie).

**Limites actuelles :**
- Régions d'atlas **approximatives** (cadrage à l'œil), pas encore de TileSet.
- La mission jouable (`MissionRoot.tscn`) garde son **rendu isométrique
  procédural** (non converti aux sprites) afin de ne pas casser le gameplay
  validé ; `BankVisualTest` sert de vitrine d'intégration. Voir `TODO.md`.

## Structure du projet

```
CLAUDE.md            # mémoire projet (concept + contraintes)
README.md            # ce fichier
TODO.md              # améliorations futures
project.godot        # config Godot 4 (autoloads, input map, web-first)
data/
  mission_01.json    # données de la mission (positions, valeurs, rondes)
scenes/              # Boot, MainMenu, MissionRoot, Player, Guard, Safe,
                     # LootBag, ExitZone, HUD, ResultScreen
scripts/             # game/save/input managers, IA, HUD, contrôles, etc.
assets/icon.svg      # icône
```

## État du MVP

**Fonctionnel et jouable :**
- Menu principal, une mission complète, écran de résultat.
- Joueur 8 directions (clavier + tactile), pause.
- 2 gardes en patrouille, cônes de vision visibles (jaune/orange/rouge),
  détection progressive, alerte globale à 100.
- Coffre avec barre de progression, 3 sacs de butin, zone de sortie.
- HUD : objectif, butin, argent, jauge d'alarme, état discret/alerte.
- Sauvegarde locale `user://save.json`.
- Pensé web-first : GL Compatibility, scènes compactes, peu d'IA actives,
  aucune dépendance native, rendu par formes (aucun asset image requis).

**Limites connues (voir `TODO.md`) :** graphismes placeholder, pas d'occlusion
visuelle des cônes par les murs, une seule mission, pas de son.
