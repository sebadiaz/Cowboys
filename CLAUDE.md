# CLAUDE.md — Mémoire projet "Dust & Dollars"

> Ce fichier est la **source de vérité** du concept. À chaque étape, on respecte
> ce document et on ne dérive pas. Si une décision technique contredit ce fichier,
> on met d'abord à jour CLAUDE.md.

## 1. Pitch

**Dust & Dollars** est un petit jeu d'arcade **2D vue de dessus** au thème
**western cartoon**. Le joueur incarne un cowboy qui **braque une banque fictive** :
il évite les gardes, récupère du butin, ouvre un coffre, gère une alarme, puis
file vers la sortie. Missions **courtes et compactes**, jouables **dans un
navigateur** (desktop et mobile).

## 2. Contraintes dures (NE PAS violer)

- Moteur : **Godot 4**, langage **GDScript uniquement** (pas de C#).
- **Pas** de plugin natif obligatoire, **pas** de dépendance native.
- **Pas** de 3D, **pas** d'open-world, **pas** de side-scroller.
- Vue **strictement de dessus (top-down)**.
- **Web-first** : export HTML5 / WebAssembly / WebGL, projet léger.
- Renderer **GL Compatibility** (meilleure compat WebGL / mobile).
- UI lisible sur **desktop et mobile browser**.
- Le prototype doit être **réellement jouable** (pas une coquille vide).

## 3. Gameplay du MVP

Le joueur contrôle un cowboy dans une banque vue de dessus. Boucle :
1. Entrer, **éviter les gardes** et leurs **cônes de vision**.
2. **Récupérer du butin** (3 sacs `$`).
3. **Ouvrir le coffre** (barre de progression en restant à proximité).
4. **Gérer l'alarme** (jauge 0→100 ; détection progressive).
5. **Atteindre la zone de sortie**.

Règles :
- **Succès** : sortir avec **au moins un butin**.
- **Échec** : un garde **en alerte** touche le joueur.
- Détection **progressive** : un garde voit le joueur → la jauge d'alarme monte.
- Alarme à **100** → tous les gardes passent en **alerte** (chasse).
- **Écran de résultat** après chaque fin de mission.

## 4. Contrôles

- Clavier : **WASD / ZQSD** (8 directions), **E** interagir, **Échap** pause.
- Mobile browser : **joystick virtuel** (gauche) + **bouton interaction** (droite).
- Abstraction via l'autoload `InputManager` (clavier + tactile fusionnés).

## 5. HUD

Affiche en permanence : **objectif courant**, **butin ramassé**, **argent gagné**,
**jauge d'alarme**, **état discret / alerte**.

## 6. Sauvegarde

Fichier `user://save.json` :
```json
{ "total_money": 0, "missions_completed": 0 }
```
Géré par l'autoload `SaveManager` (load/save robustes, valeurs par défaut).

## 7. Architecture

### Autoloads (singletons)
- `game_manager.gd` — état global, transitions de scènes, transport du résultat.
- `save_manager.gd` — lecture/écriture `user://save.json`.
- `input_manager.gd` — input unifié clavier + joystick virtuel.

### Scripts gameplay
- `player_controller.gd` — cowboy 8 directions, interactions, capture.
- `guard_ai.gd` — patrouille, états PATROL / SUSPECT / ALERTE, poursuite.
- `vision_cone.gd` — cône de vision dessiné + détection (couleur selon état).
- `alarm_system.gd` — jauge d'alarme 0→100, décroissance, alerte globale.
- `loot_system.gd` — suivi des sacs + coffre, valeur totale du butin.
- `mission_manager.gd` — construit le niveau, orchestre objectifs / fin.
- `hud_controller.gd` — HUD + menu pause.
- `mobile_controls.gd` — joystick virtuel + bouton interaction tactiles.
- `result_screen.gd` — écran de résultat + boutons rejouer / menu.

### Scènes
- `Boot.tscn` → charge la save, va au menu.
- `MainMenu.tscn` → titre + bouton Jouer / Quitter.
- `MissionRoot.tscn` → la mission jouable (construit le niveau en code).
- `Player.tscn`, `Guard.tscn`, `Safe.tscn`, `LootBag.tscn`, `ExitZone.tscn`.
- `HUD.tscn`, `ResultScreen.tscn`.

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
