# TODO — priorisé (cf. CLAUDE.md pour les règles)

## P0 — indispensable (V1 solide)

- [x] **Stabilisation (Lot 2)** : 3 banques + diligence jouées de bout en bout
      en headless (victoire ET défaite). Chaîne d'objectifs saine. Corrigés :
      spam de hit-stop sous feu nourri (jeu en diaporama), time_scale qui
      pouvait rester gelé après mission, plafond des cœurs HUD.
- [ ] **Équilibrage V1** : dégâts, vitesse alarme, agressivité — la mission 1
      doit être finissable par un débutant en mode assist.
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
- [ ] **Intérieurs in-map** avec toit transparent (banque d'abord) —
      remplace progressivement la scène mission dédiée (cf. CLAUDE.md §4).

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
