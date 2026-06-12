# TODO — priorisé (cf. CLAUDE.md pour les règles)

## P0 — indispensable (V1 solide)

- [x] **Stabilisation (Lot 2)** : 3 banques + diligence jouées de bout en bout
      en headless (victoire ET défaite). Chaîne d'objectifs saine. Corrigés :
      spam de hit-stop sous feu nourri (jeu en diaporama), time_scale qui
      pouvait rester gelé après mission, plafond des cœurs HUD.
- [x] **Équilibrage assist** : mission 1 finissable par un débutant (75 % de
      réussite mesurée même pour un bot passif qui ne riposte pas). Ajouts :
      frames d'invulnérabilité anti-rafale (clignotement), PV assist 5→7, tir
      des gardes ralenti, tireur posté défangé en assist (portée/cadence).
- [ ] **Contrôles mobiles** : valider joystick + TIR/RECH/E sur petit écran
      (480×800) ; zones de toucher assez grandes.
- [ ] **Build web testé sur navigateur réel** (perf, audio, tactile).

## P1 — important (boucle méta)

- [ ] **Carte du monde** : lisibilité + progression claire (déblocage).
- [ ] **Commerces** : armurier (armes), pharmacie (soins), magasin général
      (consommables) — écrans simples au thème `ui_theme`.
- [ ] **WantedLevelSystem** : la prime (champ `notoriety` déjà dans la save)
      a des effets : chasseurs de primes, prix d'entrée en ville.
- [ ] **JailSystem** : capture → prison → caution ou évasion courte.
- [x] **Occlusion-transparence (Lot 7)** : en ville, tout bâtiment qui masque
      le joueur devient transparent (toit/murs en alpha, fondu lissé, 8
      rotations). Système réutilisable (`town.gd` `_occlusion_target`/`_fa`).
- [ ] **Migration mission banque in-map** : dessiner la banque DANS la ville et
      réutiliser cette transparence au lieu de la scène `MissionRoot` dédiée
      (gros lot à part, cf. CLAUDE.md §4).

## P2 — polish / contenus suivants

- [ ] **HorseController** seul (montée/descente, vitesse, inertie, poussière).
- [ ] **RelativeChaseController** générique, puis **refonte diligence** dessus.
- [ ] **TrainChaseSystem** : wagons, coffre de wagon, gardes de train.
- [ ] **Saloon : jeu de cartes** arcade simple (blackjack ou poker à 1 manche).
- [ ] **Audio** : passe d'amélioration (tir plus punchy, galop, train, ambiance).

## P3 — plus tard

- [ ] **Rotation de vue 45°** (`Iso.yaw` exposé au joueur + assets directionnels).
- [ ] **Fédéraux / ville principale** (palier de difficulté final).
- [ ] **Occlusion/transparence avancée** (murs par segments, pas seulement toits).
- [ ] Localisation EN.
