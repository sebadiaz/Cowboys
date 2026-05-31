# Dust & Dollars 🤠💰

Prototype jouable d'un petit jeu d'arcade **2D vue de dessus**, thème **western
cartoon** : braque une banque fictive, évite les gardes, ouvre le coffre,
ramasse le butin et file vers la sortie. **Jouable au navigateur** (desktop et
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

1. Récupère du butin (3 sacs **$**).
2. Ouvre le **coffre** (reste à côté, maintiens **E** → barre de progression).
3. Surveille la **jauge d'alarme** : les gardes qui te voient la font monter.
   À **100**, alerte générale → tous les gardes te poursuivent.
4. Atteins la **zone de sortie verte**.

- ✅ **Réussite** : sortir avec **au moins un butin**.
- ❌ **Échec** : un garde **en alerte** te touche.

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
