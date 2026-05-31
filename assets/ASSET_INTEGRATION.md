# Intégration des assets — Dust & Dollars

> ⚠️ **Les planches actuelles sont des PLACEHOLDERS** générés par code (formes et
> couleurs simples) pour mettre en place tout le pipeline d'intégration. Remplace
> chaque PNG par ton vrai art **au même chemin et avec la même grille** (cellules
> de 128 px) : les régions d'atlas et les scènes props continueront de fonctionner
> sans rien changer.

## 1. Planches utilisées

| Fichier | Rôle |
|---|---|
| `assets/source_sheets/bank_interior_sheet.png` | Décor intérieur : sol bois, tapis, mur, comptoir |
| `assets/source_sheets/bank_props_sheet.png` | Objets : porte de coffre, coffre, sac de butin, bureau, chaise, baril, caisse, lanterne |
| `assets/source_sheets/western_exterior_sheet.png` | Extérieur : sable, façade, mur extérieur, porte |

## 2. Carte des régions (grille 128 × 128 px)

Une « cellule » `(col, row)` correspond à `region_rect = Rect2(col*128, row*128, 128, 128)`.

### bank_interior_sheet.png (4 × 1)
| Cellule | region_rect | Contenu | Prop |
|---|---|---|---|
| (0,0) | `Rect2(0,0,128,128)` | sol bois | `FloorTileProp` |
| (1,0) | `Rect2(128,0,128,128)` | tapis | `RugProp` |
| (2,0) | `Rect2(256,0,128,128)` | mur | `WallSegmentProp` |
| (3,0) | `Rect2(384,0,128,128)` | comptoir | `BankCounter` |

### bank_props_sheet.png (4 × 2)
| Cellule | region_rect | Contenu | Prop |
|---|---|---|---|
| (0,0) | `Rect2(0,0,128,128)` | porte de coffre | `VaultDoor` |
| (1,0) | `Rect2(128,0,128,128)` | coffre | `SafeProp` |
| (2,0) | `Rect2(256,0,128,128)` | sac de butin | `LootBagProp` |
| (3,0) | `Rect2(384,0,128,128)` | bureau | `DeskProp` |
| (0,1) | `Rect2(0,128,128,128)` | chaise | `ChairProp` |
| (1,1) | `Rect2(128,128,128,128)` | baril | `BarrelProp` |
| (2,1) | `Rect2(256,128,128,128)` | caisse | `CrateProp` |
| (3,1) | `Rect2(384,128,128,128)` | lanterne | *(libre)* |

### western_exterior_sheet.png (4 × 1)
| Cellule | region_rect | Contenu |
|---|---|---|
| (0,0) | `Rect2(0,0,128,128)` | sable |
| (1,0) | `Rect2(128,0,128,128)` | façade |
| (2,0) | `Rect2(256,0,128,128)` | mur extérieur |
| (3,0) | `Rect2(384,0,128,128)` | porte |

## 3. Scènes props créées (`scenes/props/`)

| Scène | Source | Collision |
|---|---|---|
| `FloorTileProp.tscn` | interior (0,0) | non |
| `RugProp.tscn` | interior (1,0) | non |
| `WallSegmentProp.tscn` | interior (2,0) | StaticBody2D (carré) |
| `BankCounter.tscn` | interior (3,0) | StaticBody2D |
| `VaultDoor.tscn` | props (0,0) | StaticBody2D |
| `SafeProp.tscn` | props (1,0) | StaticBody2D |
| `LootBagProp.tscn` | props (2,0) | non (visuel) |
| `DeskProp.tscn` | props (3,0) | StaticBody2D |
| `ChairProp.tscn` | props (0,1) | non |
| `BarrelProp.tscn` | props (1,1) | StaticBody2D (cercle) |
| `CrateProp.tscn` | props (2,1) | StaticBody2D |

Chaque prop = `Node2D` racine + `Sprite2D` (texture + région d'atlas) + éventuel
`StaticBody2D/CollisionShape2D` quand l'objet doit bloquer le joueur.

## 4. Comment fonctionnent les régions d'atlas

Plutôt que de découper la planche en fichiers séparés, chaque `Sprite2D` pointe
sur **la planche entière** et n'affiche qu'un rectangle :

```gdscript
sprite.texture = preload("res://assets/source_sheets/bank_props_sheet.png")
sprite.region_enabled = true
sprite.region_rect = Rect2(128, 0, 128, 128)  # le coffre
```

En `.tscn` :

```
[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("1")
region_enabled = true
region_rect = Rect2(128, 0, 128, 128)
```

Avantages : une seule texture chargée (léger pour le web), découpage ajustable
sans réimporter d'assets.

## 5. Séparation visuel / gameplay (important)

Les props visuels **ne portent pas** la logique de jeu. Le gameplay reste dans
les scènes existantes :

- Visuel : `scenes/props/*.tscn` (Sprite2D, +collision décorative éventuelle).
- Gameplay : `LootBag.tscn` (Area2D + `loot_system.gd`), `Safe.tscn`
  (Area2D + `safe.gd`), `ExitZone.tscn`, `Guard.tscn`, `Player.tscn`, etc.

Pour habiller un objet de gameplay, on lui **ajoute** un `Sprite2D` (ou on
instancie le prop visuel comme enfant) sans toucher à son script ni ses signaux.

> Note d'architecture : la mission jouable (`MissionRoot.tscn`) utilise un
> **rendu isométrique procédural** (`iso_renderer.gd`) ; elle n'a donc pas été
> convertie aux sprites pour ne pas casser le gameplay validé. La vitrine
> `scenes/levels/BankVisualTest.tscn` démontre l'intégration des décors. La
> migration du rendu de mission vers les sprites est listée dans `TODO.md`.

## 6. Remplacer les placeholders par du vrai art

1. Exporte ton vrai art en gardant la **même grille 128 px** et la **même
   disposition** que la section 2 (ou ajuste les `region_rect` dans les props).
2. Écrase les fichiers dans `assets/source_sheets/` (mêmes noms).
3. Réimporte dans Godot (automatique à l'ouverture de l'éditeur).
4. Si tes cellules ont une autre taille, mets à jour les `region_rect` des props
   concernés (et au besoin les `CollisionShape2D`).
5. Étape suivante recommandée : remplacer les régions approximatives par un vrai
   **TileSet** Godot (`assets/tilesets/`) pour le sol/murs, et par des PNG
   découpés individuels dans `assets/props/` si tu préfères.
