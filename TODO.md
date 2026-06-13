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

- [x] **Carte du monde (Lot 12)** : légende des états (conquise / à conquérir /
      verrouillée + difficulté), pastilles de difficulté par ville, bannière
      « À CONQUÉRIR » sur la frontière, noms dé-encombrés (placement anti-collision,
      lignes de rappel, seules les villes pertinentes nommées).
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

- [x] **HorseController (Lot 16)** : cheval montable en ville (E pour monter/
      descendre, vitesse ×1.9, inertie/galop, cavalier dessiné, poussière).
      Système isolé `horse_controller.gd`, prêt pour les poursuites.
- [x] **RelativeChaseController (Lot 17)** : déplacement relatif à une cible
      mobile (avancer/reculer + latéral), monde qui défile, tir. Banc d'essai
      `ChaseTest.tscn` (bouton menu). Reste : poser la diligence/le train dessus.
- [x] **Refonte diligence (Lot 18)** : `stagecoach_chase.gd` sur le chase relatif
      — rattraper → piller le coffre à hauteur (E) → décrocher pour fuir ; escorte
      montée qui riposte, équipe (CrewScreen) qui chevauche et tire, HUD + résultat
      + bande fidèle réutilisés. Routée par `start_coach_attack()`. Vérifiée
      (victoire et échec en headless). Reste : train (lot 19) sur la même base.
- [x] **TrainChaseSystem (Lot 19)** : `train_chase.gd` sur le chase relatif —
      locomotive + 4 wagons, on longe le convoi et pille chaque wagon (E à hauteur),
      wagon d'OR = objectif, gardes postés sur les toits, décrochage pour fuir.
      Bouton « ATTAQUER LE TRAIN » dans CrewScreen. Vérifié headless (4/4 wagons,
      1740 $, victoire). Bande du RelativeChaseController rendue réglable par instance.
- [ ] **Saloon : jeu de cartes** arcade simple (blackjack ou poker à 1 manche).
- [ ] **Audio** : passe d'amélioration (tir plus punchy, galop, train, ambiance).

## P3 — plus tard

- [ ] **Rotation de vue 45°** (`Iso.yaw` exposé au joueur + assets directionnels).
- [ ] **Fédéraux / ville principale** (palier de difficulté final).
- [ ] **Occlusion/transparence avancée** (murs par segments, pas seulement toits).
- [ ] Localisation EN.
