# CLAUDE.md — Mémoire projet "Dust & Dollars"

> Ce fichier est la **source de vérité** du concept. À chaque étape, on respecte
> ce document et on ne dérive pas. Si une décision technique contredit ce fichier,
> on met d'abord à jour CLAUDE.md.

## 1. Pitch

**Dust & Dollars** est un petit jeu d'arcade **2D en vue isométrique** au thème
**western cartoon**. Le joueur incarne un cowboy qui **braque une banque fictive** :
il **dégaine son pistolet**, abat ou évite les gardes, récupère du butin, ouvre un
coffre, gère une alarme, puis file vers la sortie. Missions **courtes et
compactes**, jouables **dans un navigateur** (desktop et mobile).

## 2. Contraintes dures (NE PAS violer)

- Moteur : **Godot 4**, langage **GDScript uniquement** (pas de C#).
- **Pas** de plugin natif obligatoire, **pas** de dépendance native.
- **Pas** de 3D (vraie 3D interdite), **pas** d'open-world, **pas** de side-scroller.
- Vue **isométrique 2D** : la simulation (déplacements, collisions, détection)
  reste en coordonnées **cartésiennes top-down** ; seul le **rendu** est projeté
  en isométrique (projection 2:1) avec **tri de profondeur**. Personnages dessinés
  **debout**, sol/murs en losange. Aucune 3D réelle.
- Contrôles clavier **alignés écran** (l'input est pivoté de 45° vers le monde).
- **Web-first** : export HTML5 / WebAssembly / WebGL, projet léger.
- Renderer **GL Compatibility** (meilleure compat WebGL / mobile).
- UI lisible sur **desktop et mobile browser**.
- Le prototype doit être **réellement jouable** (pas une coquille vide).

## 3. Gameplay du MVP

Le joueur contrôle un cowboy dans une banque vue de dessus. Boucle :
1. Entrer, **éviter ou abattre les gardes** (cônes de vision).
2. **Tirer au pistolet** : abattre les gardes ; les gardes en alerte ripostent.
3. **Récupérer du butin** (3 sacs `$`).
4. **Ouvrir le coffre** (barre de progression en restant à proximité).
5. **Gérer l'alarme** (jauge 0→100 ; détection progressive).
6. **Atteindre la zone de sortie**.

Règles :
- **Succès** : sortir avec **au moins un butin**.
- **Combat** : le joueur tire **à l'arrêt uniquement** (pas de tir en
  mouvement) ; une balle abat un garde. Les gardes **en alerte** tirent sur lui.
- **Points de vie** : le joueur a **3 PV** ; à **0 PV** (balles / contact garde
  en alerte) → échec.
- Détection **progressive** : un garde voit le joueur → la jauge d'alarme monte.
- Alarme à **100** → tous les gardes passent en **alerte** (chasse + tir).
- **Écran de résultat** après chaque fin de mission.

## 4. Contrôles

- Clavier : **WASD / ZQSD** (8 directions), **Espace / clic** tirer, **R**
  recharger, **E** interagir, **Échap** pause.
- Mobile browser : **joystick virtuel** (gauche) + boutons **TIR**, **RECH** et
  **E** (droite).
- Le tir s'oriente vers le **point cliqué** (souris) ; repli sur la direction
  regardée pour le bouton tactile TIR.
- **Six-coups** : barillet de **6 balles**, **rechargement lent** (~1,6 s) — auto
  quand vide, ou manuel (R / RECH).
- Abstraction via l'autoload `InputManager` (clavier + tactile fusionnés).

## 4 bis. Flux de jeu

Menu → **Ville (extérieur western)** : on arrive en ville et on rejoint la
**banque** à pied (porte) → la **mission de braquage** démarre → écran de
résultat. Scène `Town.tscn` (décor depuis `western_exterior_sheet.png`).

## 5. HUD

Affiche en permanence : **objectif courant**, **butin ramassé**, **argent gagné**,
**jauge d'alarme**, **points de vie**, **état discret / alerte**.

## 6. Sauvegarde

Fichier `user://save.json` :
```json
{ "total_money": 0, "missions_completed": 0,
  "upgrades": { "speed": 0, "safe": 0, "reload": 0, "stealth": 0 } }
```
Géré par l'autoload `SaveManager` (load/save robustes, valeurs par défaut).
Rétrocompatible : une save sans `upgrades` est lue sans planter (valeurs 0).

## 6 bis. Vision fun / arcade V2

Objectif : un vrai **feeling de braquage** nerveux et rejouable, sans refonte.

- **Game juice** : screen-shake au tir/impact, recul du joueur, flash de touche
  des gardes, particules (poussière de pas, étincelles, impact, douilles,
  gerbe dorée au ramassage), animation de mort des gardes, vignette d'ambiance,
  overlay rouge **pulsé** quand l'alarme monte.
- **Tir western** : six-coups de 6 balles, recharge auto/manuelle, cadence
  lisible (pan… pan… pause… reload), visée au clic / direction tactile.
- **IA gardes** : `PATROL → SUSPECT → SEARCH → ALERT`. Mémoire de la **dernière
  position connue** + fouille temporisée ; **renfort** déclenché à l'alarme 100.
- **Drame** : messages courts (`VU !`, `ALARME !`, `COFFRE OUVERT !`, `FUITE !`),
  objectif courant clair, montée de tension visuelle + sonore.
- **Audio procédural** : autoload `AudioManager` qui **synthétise** les sons
  (tir, reload, ramassage, coffre, alarme, hit, victoire/échec) — aucun asset
  audio requis, web-compatible.
- **Progression** : score de mission = butin + coffre + **bonus discrétion** +
  **bonus temps** ; **boutique** d'upgrades (vitesse, coffre, recharge,
  discrétion) persistés dans la save et appliqués en mission.

## 7. Architecture

### Autoloads (singletons)
- `game_manager.gd` — état global, transitions de scènes, transport du résultat.
- `save_manager.gd` — lecture/écriture `user://save.json`.
- `input_manager.gd` — input unifié clavier + joystick virtuel.

### Autoloads (suite)
- `audio_manager.gd` — sons **synthétisés** à la volée (pas d'asset audio).

### Scripts gameplay
- `player_controller.gd` — cowboy 8 directions, tir six-coups, interactions.
- `guard_ai.gd` — patrouille, états PATROL / SUSPECT / SEARCH / ALERT, mémoire
  de la dernière position connue, riposte.
- `vision_cone.gd` — cône de vision dessiné + détection (couleur selon état).
- `alarm_system.gd` — jauge d'alarme 0→100, décroissance, alerte globale.
- `loot_system.gd` — suivi des sacs + coffre, valeur totale du butin.
- `mission_manager.gd` — construit le niveau, orchestre objectifs / score / fin,
  renforts, effets et audio.
- `effects.gd` — particules, screen-shake (rendu dans l'espace du renderer).
- `hud_controller.gd` — HUD + menu pause + flash + overlay d'alerte pulsé.
- `mobile_controls.gd` — joystick virtuel + boutons TIR / RECH / E tactiles.
- `result_screen.gd` — écran de résultat (détail du score) + rejouer / menu.
- `shop_screen.gd` — boutique d'upgrades (achat via le magot, persisté).

### Scènes
- `Boot.tscn` → charge la save, va au menu.
- `MainMenu.tscn` → titre + boutons Jouer / Boutique / Quitter.
- `MissionRoot.tscn` → la mission jouable (construit le niveau en code).
- `Player.tscn`, `Guard.tscn`, `Safe.tscn`, `LootBag.tscn`, `ExitZone.tscn`.
- `HUD.tscn`, `ResultScreen.tscn`, `ShopScreen.tscn`.

## 8. Assets temporaires (formes Godot, pas d'images requises)

Tout est dessiné via `_draw()` pour rester léger et sans assets externes :
- Joueur : corps **marron** + **chapeau**.
- Gardes : **bleus**.
- Cônes de vision : **jaune** (calme) → **orange** (suspect) → **rouge** (alerte).
- Coffre : **gris**. Sacs : **jaunes** avec **`$`**. Sortie : **verte**.
- Murs / comptoirs : rectangles simples.

## 9. Méthode de travail

1. Respecter cette structure de dossiers : `scenes/ scripts/ data/ assets/`.
2. Code **simple, robuste, fonctionnel** ; pas de fichier vide inutile.
3. Peu d'IA actives (2 gardes) ; scènes compactes ; caméra fixe sur le niveau.
4. Le projet doit s'ouvrir dans Godot 4, se lancer, et permettre de jouer une
   **mission complète** (gardes, alarme, coffre, butin, sortie, résultat).

## 10. État

MVP fonctionnel jouable. Améliorations futures listées dans `TODO.md`.
