# TODO — Améliorations futures de Dust & Dollars

Le MVP est jouable. Pistes d'évolution, sans dériver du concept (cf. `CLAUDE.md`) :

## Fait dans la passe "arcade V2" (cf. CLAUDE.md §6 bis)
- [x] Game juice : screen-shake, recul joueur, flash de touche des gardes.
- [x] Particules : poussière de pas, étincelles, impact de balle, douilles,
      gerbe dorée au ramassage ; animation de mort des gardes.
- [x] Vignette d'ambiance + overlay rouge **pulsé** quand l'alarme monte.
- [x] Tir six-coups (6 balles), recharge auto/manuelle, cadence western.
- [x] IA gardes : état `SEARCH` + dernière position connue + fouille ; **renfort**
      déclenché à l'alarme 100 ; gardes à 2 PV.
- [x] Messages dramatiques : `VU !`, `ALARME !`, `COFFRE OUVERT !`, `FUITE !`.
- [x] Audio **procédural** (autoload `AudioManager`, aucun asset).
- [x] Scoring (butin + coffre + bonus discrétion + bonus temps) + **boutique**
      d'upgrades (vitesse, coffre, recharge, discrétion) persistés dans la save.
- [x] Rendu adapté à la taille d'écran (zoom auto, mobile + desktop).

## Direction artistique
- [x] **Cowboy charismatique** dessiné en couches (chapeau, bandana, duster,
      ceinturon/holster, bottes, visage), directionnel + animé.
- [x] Gardes shérifs distincts (manteau bleu, étoile).
- [ ] Sprites PNG animés (remplacer le rendu procédural par des planches).
- [ ] Animation de mort plus riche (le corps reprend le style du cowboy).
- [ ] Vrais bruitages / musique western (remplacer l'audio procédural).

## Assets & intégration (suite)
- [x] Intégrer les vraies planches PNG (1254²) + props en régions d'atlas.
- [ ] **Cadrage précis des régions** au pixel (les `region_rect` sont à l'œil).
- [ ] Exploiter `western_exterior_sheet.png` (scène d'extérieur / rue).
- [ ] Créer un **vrai TileSet Godot** (`assets/tilesets/`) pour sol et murs.
- [ ] **Collisions plus précises** sur les props (formes ajustées au visuel).
- [ ] **Séparation définitive** props décoratifs / objets gameplay.
- [ ] **Migrer le rendu de `MissionRoot`** vers les sprites des planches
      (dessiner les régions d'atlas dans `iso_renderer.gd` au lieu des formes).
- [ ] **Occlusion des cônes de vision par les murs** (découpe visuelle du cône).

## Gameplay & IA
- [ ] **Occlusion des cônes de vision par les murs** (découpe visuelle du cône).
- [ ] Mode **tactique ralenti** (bullet-time pour planifier).
- [x] **Shérifs supplémentaires** et renforts quand l'alarme est pleine.
- [x] Mémoire des gardes (dernière position connue, fouille de zone).
- [ ] Phase de **fuite à cheval** après le braquage.

## Contenu & progression
- [ ] **Carte du monde** et plusieurs **villes** / banques.
- [ ] Plusieurs missions avec objectifs variés.
- [x] **Boutique** et **upgrades** (vitesse, coffre rapide, recharge, discrétion).
- [ ] Nouveaux types d'upgrades (leurres, plus de PV, chargeur+).
- [ ] **Vraie minimap** en jeu.

## Audio
- [x] **Sons procéduraux** (tir, reload, ramassage, coffre, alarme, hit, fin).
- [ ] **Vrais bruitages** + **musique** western (ambiance).

## Technique / plateforme
- [ ] **PWA** (installable, jouable hors-ligne).
- [ ] Export **Android / iOS** natif.
- [ ] Réglages : volume, sensibilité du joystick, taille des contrôles tactiles.
- [ ] Localisation (FR/EN).
