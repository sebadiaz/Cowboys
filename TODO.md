# TODO — Améliorations futures de Dust & Dollars

Le MVP est jouable. Pistes d'évolution, sans dériver du concept (cf. `CLAUDE.md`) :

## Direction artistique
- [ ] Vrais graphismes (sprites animés joueur/gardes, tuiles de banque).
- [ ] Animations de marche 8 directions, feedback de capture.
- [ ] Effets : poussière, flash d'alarme, particules sur le coffre.

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
- [ ] **Shérifs supplémentaires** et renforts quand l'alarme est pleine.
- [ ] Mémoire des gardes (dernière position connue, fouille de zone).
- [ ] Phase de **fuite à cheval** après le braquage.

## Contenu & progression
- [ ] **Carte du monde** et plusieurs **villes** / banques.
- [ ] Plusieurs missions avec objectifs variés.
- [ ] **Boutique** et **upgrades** (vitesse, crochetage plus rapide, leurres).
- [ ] **Vraie minimap** en jeu.

## Audio
- [ ] **Sons** (pas, alarme, coffre, ramassage) et **musique** western.

## Technique / plateforme
- [ ] **PWA** (installable, jouable hors-ligne).
- [ ] Export **Android / iOS** natif.
- [ ] Réglages : volume, sensibilité du joystick, taille des contrôles tactiles.
- [ ] Localisation (FR/EN).
