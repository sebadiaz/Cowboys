# TODO — Améliorations futures de Dust & Dollars

Le MVP est jouable. Pistes d'évolution, sans dériver du concept (cf. `CLAUDE.md`) :

## Fait dans la passe "village explorable"
- [x] **Ville EL DORADO** visitable : grande carte, rue principale, 7 commerces
      nommés (Banque, Saloon, Hôtel, Magasin, Shérif, Écurie, Poste), **PNJ**
      cowboys, props (chariot, tonneaux, cactus, panneaux), trottoirs en bois.
- [x] **Dialogues** : E pour parler aux habitants (répliques qui défilent).
- [x] **PNJ vivants** (`npc_ai.gd`) : déambulation avec collisions, coups d'œil,
      bulles d'ambiance ; ils s'arrêtent et se tournent vers toi quand tu parles.
- [x] **Saloon entrable** (intérieur : barman, clients, pianiste, piano, tables,
      comptoir) avec dialogues, sortie qui ramène en ville.
- [x] **Pianiste qui joue** une mélodie honky-tonk (notes piano synthétisées).
- [x] **Magasin entrable** → ouvre la **boutique d'upgrades** (retour en ville).
- [x] **Diligence** qui traverse la grande rue (chevaux + poussière).
- [x] **Logo d'action cliquable** devant les portes/cibles (🚪/🛒/💬/👁/🐴).
- [x] **Décor solide** : collisions sur les meubles (banques : tonneaux/caisses/
      bureaux) et les props de ville (tonneaux, cactus, chariots, panneaux, puits).
- [x] **Ville + saloon passés au vrai moteur physique** : joueur CharacterBody2D
      + StaticBody2D par décor (sous-arbre top_level hors caméra) → on ne traverse
      plus rien, glissement le long des murs.
- [x] **Chevaux attachés** devant l'écurie (décor solide + on peut les caresser).
- [x] **Collisions** sur les bâtiments (on ne traverse plus les murs).
- [x] Caméra qui suit le cowboy (ville + saloon) ; banque repérable + flèche.
- [x] Entrée banque/saloon sur **E** (clavier + bouton tactile).
- [x] Rendu du cowboy **mutualisé** (`character_art.gd`) entre ville et mission.

## Fait dans la passe "grande banque + cowboy"
- [x] **Grande banque** (1480×840) : hall étendu, zone personnel, bureau, salle
      des coffres refermée, **aile droite** ; 7 sacs, 4 gardes.
- [x] Décor enrichi : tapis (prestige coffre / hall / entrée), lampes d'ambiance,
      tonneaux/caisses/bureaux de couverture.
- [x] Accessibilité vérifiée (BFS) : aucune entité dans un mur, tout atteignable.

## Fait dans la passe "carte du monde + villes"
- [x] **Carte du monde** (`WorldMap.tscn`/`world_map.gd`) façon parchemin western :
      reliefs, rivière, cactus, rose des vents, **piste en pointillés** reliant
      plusieurs **villes** (pastilles cliquables, desktop + mobile).
- [x] **Plusieurs villes** (`GameManager.TOWNS`) avec **ambiances distinctes**
      (désert doré, canyon rouge, neige argentée…), chacune liée à **sa banque**.
- [x] **Déblocage progressif** des villes (selon `levels_unlocked`) + villes
      « à venir » en teaser ; pulse « tu es ici » sur la ville courante.
- [x] Flux : Menu → **Carte** → Ville (thématisée) → Banque → mission.

## Carte du monde — pistes suivantes
- [ ] **Layouts de ville uniques** par biome (pas seulement la teinte).
- [ ] Déplacement animé d'un **pion** le long de la piste entre deux villes.
- [ ] Plus de villes + nouvelles banques (étendre `data/mission_0N.json`).

## Fait dans la passe "refonte visuelle de la banque"
- [x] **Intérieur de banque premium** dessiné en procédural dans `iso_renderer.gd`
      (remplace les billboards d'atlas placeholder) : parquet bicolore, murs
      lambrissés (plinthe/corniche) vs murs brique extérieurs.
- [x] **Comptoir de guichets** continu (base bois moulurée + cage laiton « BANK »).
- [x] **Grande porte de coffre** : disque acier, couronne de rivets, volant à
      rayons doré, charnières, plaque « BANQUE » — pièce maîtresse ; intérieur
      doré révélé à l'ouverture.
- [x] **Props cohérents cartoon** : caisses (croix + ferrures), tonneaux, bureaux
      de banquier (feutre vert + lampe + registre), coffre secondaire (strongbox),
      étagères à registres + sacs d'or, plantes, affiches WANTED, lampes, sacs de
      butin dorés bien lisibles.
- [x] **Hiérarchie lisible** entrée → hall → comptoir → coffre → sortie ; décor
      ajouté sur les 3 niveaux **sans toucher aux collisions** (props décoratifs
      non bloquants, patrouilles préservées).

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
- [x] **3 niveaux** (banques distinctes) pilotés par les données, débloqués au
      fil des réussites + écran de **sélection de niveau**.
- [ ] **Carte du monde** et plusieurs **villes**.
- [ ] Plus de niveaux + objectifs variés (otages, coffre à temps, etc.).
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
