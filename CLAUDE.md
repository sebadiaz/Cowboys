# CLAUDE.md — Mémoire projet « Dust & Dollars » (Cowboys)

> Source de vérité. Tout LLM/dev lit ce fichier AVANT de coder.
> Si une décision technique contredit ce fichier, on met d'abord à jour CLAUDE.md.

## 1. Vision

Western **ARCADE 2D** (pas un RPG). Le joueur est un hors-la-loi : braquages de
banques, attaques de diligences puis de trains, fuite à cheval, villes sur une
carte du monde, prime sur la tête, commerces (saloon, armurier, pharmacie,
magasin général), prison, fédéraux dans la ville principale, jeux de cartes au
saloon. Missions **courtes (2–5 min)**, rejouables, lisibles. Construit par
**couches successives** : chaque version livre un jeu jouable de bout en bout.

## 2. Contraintes dures (NE PAS violer)

- Godot 4.x, **GDScript uniquement**, renderer **GL Compatibility**,
  export Web (preset « Web » → `build/web/`, gitignoré).
- Pas de C#, pas de plugin natif, pas de vraie 3D, pas d'open-world.
- Web + mobile : joystick virtuel + boutons tactiles (déjà en place via
  `InputManager` / `mobile_controls.gd`).
- Assets : **CC0 uniquement** (Kenney) ; licences dans `assets/sprites/`.
  Sons **synthétisés** par `AudioManager` (aucun asset audio).
- Save `user://save.json` via `SaveManager`, **rétrocompatible** (jamais de
  crash sur une vieille save).

## 3. Règle isométrie / rotation 45° (séparation logique/rendu)

- La **simulation** (déplacement, collisions, IA, balles, détection) est
  TOUJOURS en coordonnées **cartésiennes top-down**. Jamais de logique en
  coordonnées écran.
- Le **rendu** passe par le helper statique `Iso` (`scripts/iso.gd`) :
  `project / unproject / depth / screen_to_world`. Deux modes :
  **iso 2:1** avec `Iso.yaw` (vue pivotable par pas de 45° : 0°…315°) et
  **top-down** (`Iso.top_down = true`, projection identité — mode actuel des
  missions, rendu sprites).
- Conséquence : la rotation 45° est un problème de **rendu seulement**
  (yaw + assets directionnels). Elle ne bloque jamais le gameplay et n'est pas
  requise en V1.
- Tout nouveau renderer suit ce contrat : il lit des positions **monde** et projette.

## 4. Règle bâtiments (intérieurs visibles)

- Cible : on **n'entre pas** dans une scène séparée pour chaque commerce. Le
  bâtiment **reste sur la carte** de la ville ; quand le joueur est dedans (ou
  masqué), le **toit / les murs proches deviennent transparents** (occlusion alpha).
- **Lisibilité > réalisme.** S'applique à : banque, saloon, armurier,
  pharmacie, magasin, prison, bureau du shérif.
- **FAIT (ville iso, `town.gd`)** : occlusion-transparence opérationnelle — tout
  bâtiment qui masque le joueur (dessiné par-dessus lui + couvre sa silhouette)
  passe en alpha ~0.3, fondu lissé, valable aux 8 rotations. Voir
  `_occlusion_target()` + `_fade`/`_fa()`. Réutilisable pour tout bâtiment posé
  sur la carte.
- **FAIT (commerces in-map)** : les 3 commerces (FORGE=armurier, DOCTEUR=pharmacie,
  MAGASIN=magasin) sont sur le MÊME PLAN que la rue — collision en 3 murs (front
  ouvert), on entre par la porte, le toit passe en alpha ~0.18 (footprint), un
  intérieur est dessiné (sol bois, comptoir, tenancier, accents métier) et une
  **carte d'achat NON-MODALE** s'ouvre seule à droite (ville visible derrière, pas
  de changement de scène) puis se ferme quand on ressort. Voir `_draw_interior`,
  `_update_commerce_card`, `_building_inside`.
- **FAIT (banque in-map)** : le BRAQUAGE est désormais sur le MÊME PLAN que la rue
  (plus de scène `MissionRoot` ni de carré vert) : on entre par la porte (toit
  transparent), on force le coffre dans le hall (E -> crochetage auto, barre de
  progression), on encaisse le butin + déblocage de la ville suivante, la notoriété
  monte (les chasseurs de primes peuvent débarquer) puis on ressort par la rue —
  linéaire, sans changement de scène. Voir `_update_bank_heist`, `_crack_vault`,
  `_vault_world`. La scène `MissionRoot` reste pour les niveaux rapides/sélection.

## 5. Règle cheval / train / diligence (poursuites)

- Poursuite = systèmes **séparés et composables** :
  - `HorseController` : la monture seule (montée/descente, vitesse, inertie).
  - `RelativeChaseController` : le monde défile ; le joueur se déplace
    **relativement** à la cible (gauche/droite, avancer/reculer).
  - `TrainChaseSystem` / `StagecoachChaseSystem` : contenus posés par-dessus
    (wagons, coffres, ennemis, interactions E).
- Le train / la diligence **avance en continu** ; le joueur tire et interagit
  depuis le cheval. **Ne jamais fusionner** cheval+train+diligence en un script.

## 6. V1 (jouable, fun) — état : LARGEMENT FAITE

Ville → banque → braquage : déplacement 8 dir, tir six-coups (6 balles,
recharge lente, tir à l'arrêt), gardes à cône de vision
(PATROL/SUSPECT/SEARCH/ALERT) + snipers, butin, coffre, alarme 0→100, fuite,
victoire/défaite, HUD dessiné, contrôles tactiles, mode assist (5 PV), boutique
d'upgrades, carte du monde (villes procédurales), mission diligence (convoi
mobile). **NE PAS refaire ; stabiliser et polir seulement.**

## 7. Systèmes & fichiers

- **Autoloads** : `game_manager.gd` (états/transitions), `save_manager.gd`,
  `input_manager.gd` (clavier+tactile), `audio_manager.gd` (SFX+musique synthétisés).
- **Gameplay** : `player_controller`, `guard_ai` (+sniper), `bullet_system`,
  `alarm_system`, `loot_system`, `ally_ai` (équipe diligence),
  `mission_manager` (niveaux pilotés par `data/mission_0N.json` + génération
  procédurale ; orchestre tout).
- **Rendu** : `iso.gd` (projection), `top_down_renderer.gd` (missions, sprites
  CC0), `town.gd` / `saloon.gd` (iso), `effects.gd` (particules, shake,
  hit-stop), `character_art.gd` (persos iso dessinés).
- **UI** : `hud_controller` + `hud_gfx` (HUD dessiné cuir/or), `ui_theme` +
  `ui_backdrop` (menus western), `mobile_controls`, `result_screen`,
  `shop_screen`, `crew_screen`, `world_map`, `settings_screen`.
- **Monture** : `horse_controller.gd` (FAIT, lot 16) — système isolé (état
  monté, vitesse, inertie/galop). Intégré en ville (`town.gd` : monter/descendre
  E, cavalier dessiné, poussière).
- **Poursuite** : `relative_chase_controller.gd` (FAIT, lot 17) — système isolé :
  offset du joueur dans le repère de la cible (avancer/reculer + latéral), borné
  à une bande, états à-hauteur / distancé. Banc d'essai `scenes/levels/ChaseTest.tscn`
  (+ bouton menu « POURSUITE (prototype) »).
- **Diligence** : `stagecoach_chase.gd` (FAIT, lot 18) — vraie poursuite posée sur
  `RelativeChaseController` + `HorseController` : la diligence roule en continu,
  on la rattrape, on se met à hauteur pour piller le coffre (maintien E), l'escorte
  montée riposte, l'équipe (CrewScreen) chevauche et tire, puis on décroche pour
  fuir. Réutilise le HUD, le flux résultat/score et la promotion en bande fidèle.
  Lancée par `GameManager.start_coach_attack()` (scène `StagecoachChase.tscn`).
  L'ancien mode coach de `mission_manager` n'est plus routé (conservé, non supprimé).
- **Données** : `data/mission_0N.json`, `data/coach.json`.
  Sprites : `assets/sprites/` (Tiny Town = décor, Tiny Dungeon = personnages).
- **Train** : `train_chase.gd` (FAIT, lot 19, sur le chase relatif) — locomotive +
  wagons en file ; avancer/reculer longe le convoi, on pille chaque wagon (E à
  hauteur), le wagon d'OR au bout = objectif, gardes postés sur les toits, puis on
  décroche. Lancé par `GameManager.start_train_attack()` (scène `TrainChase.tscn`),
  bouton dédié dans CrewScreen. Réutilise HUD/équipe/résultat/bande comme la diligence.
- **Commerces** : `shop_screen.gd` filtré par `GameManager.shop_category` (FAIT,
  lot 13) — ARMURIER (FORGE), CABINET DU DOC (DOCTEUR), MAGASIN GÉNÉRAL (MAGASIN),
  enterables en ville via `goto_commerce()`. Catalogue catégorisé (champ `store`).
- **Prison** : `jail_system.gd` (FAIT, lot 15, scène `Jail.tscn`) — un braquage de
  banque RATÉ y mène (pris par la loi) ; sortie par caution (magot, scale notoriété)
  ou crochetage (mini-jeu d'adresse). S'évader augmente la prime. Diligence/train
  ratés = mort en plein air -> écran de résultat (pas de prison).
- **Prime** : `wanted_system.gd` (FAIT, lot 14) — système isolé : au-delà d'un seuil
  de notoriété (4), des chasseurs de primes apparaissent en ville et traquent le
  joueur (seek + évitement via `_blocked`). Plus lents qu'à pied, bien plus lents
  que le cheval -> on peut fuir. Capturé = ils empochent une part de la prime et la
  traque retombe. Intégré dans `town.gd` (rendu + bandeau PRIME + conséquence).
- **À créer plus tard (lots dédiés)** : 
  migration mission banque in-map, `card_game` (saloon).

## 8. Interdits (toutes versions)

- Pas de RPG : pas de dialogues à branches, pas de quêtes longues, pas
  d'inventaire complexe, pas de craft.
- Pas de refonte globale non demandée ; pas de renommage massif ;
  pas de nouvelle dépendance ; pas d'asset non-CC0.
- Pas de logique gameplay en coordonnées écran (passer par `Iso`).
- Un lot = un périmètre. On ne touche pas aux autres systèmes.

## 9. Checklist avant de terminer une tâche

1. `godot --headless --import` puis lancer la scène touchée : **zéro** erreur
   de parse/script.
2. Mission 1 jouable de bout en bout (ou l'écran touché fonctionnel).
3. Export web OK : `godot --headless --export-release "Web" build/web/index.html`.
4. Vieille save chargée sans crash ; boutons tactiles non cassés.
5. CLAUDE.md / TODO.md mis à jour si la réalité a changé.
6. Commit clair + push sur la branche de travail. Résumer les fichiers modifiés.
