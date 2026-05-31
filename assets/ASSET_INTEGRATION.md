# Intégration des assets — Dust & Dollars

Les décors viennent de **3 planches PNG (1254 × 1254)** placées dans
`assets/source_sheets/`. Les props les utilisent via des **régions d'atlas**
(`Sprite2D.region_rect`) — aucune image découpée individuellement.

> ℹ️ Les `region_rect` ci-dessous sont **approximatifs** (cadrage à l'œil sur le
> vrai art). Si un objet est mal cadré, ajuste son `region_rect` dans la scène
> prop correspondante (`scenes/props/*.tscn`).

## 1. Planches et leur contenu réel

> ⚠️ Attention : le **contenu ne correspond pas au nom de fichier**.

| Fichier | Contenu réel |
|---|---|
| `bank_props_sheet.png` | **Éléments de bâtiment** : sols, murs, coins de mur, comptoirs « BANK », portes, fenêtres, tapis |
| `bank_interior_sheet.png` | **Objets** : porte de coffre, coffre, bureau, chaise, table+lampe, lanterne, barils, seau, plante, caisses, sacs `$`, lingots, poster WANTED, livres, parchemin |
| `western_exterior_sheet.png` | **Extérieurs** : sols de sable, rochers, barrières, cactus, chariot, baril, caisse, panneaux, abreuvoir, crâne, façades de bâtiments |

## 2. Régions utilisées par les props (en pixels)

`region_rect = Rect2(x, y, w, h)`. Sprite `centered = true` → la région est
centrée sur l'origine du prop.

### Depuis `bank_props_sheet.png` (bâtiment)
| Prop | region_rect | Contenu |
|---|---|---|
| `FloorTileProp` | `Rect2(25, 25, 300, 280)` | dalle de sol bois |
| `WallSegmentProp` | `Rect2(395, 350, 215, 175)` | segment de mur |
| `BankCounter` | `Rect2(25, 770, 620, 190)` | comptoir « BANK » |
| `RugProp` | `Rect2(1000, 1000, 245, 245)` | tapis rouge |

### Depuis `bank_interior_sheet.png` (objets)
| Prop | region_rect | Contenu |
|---|---|---|
| `VaultDoor` | `Rect2(50, 40, 340, 300)` | porte de coffre |
| `SafeProp` | `Rect2(425, 50, 235, 295)` | coffre |
| `DeskProp` | `Rect2(685, 60, 290, 275)` | bureau |
| `ChairProp` | `Rect2(520, 385, 180, 235)` | chaise |
| `BarrelProp` | `Rect2(60, 635, 160, 210)` | baril |
| `CrateProp` | `Rect2(60, 855, 180, 200)` | caisse |
| `LootBagProp` | `Rect2(845, 855, 175, 205)` | sac de butin `$` |

`western_exterior_sheet.png` n'est pas encore référencé par un prop : réservé aux
futures scènes d'extérieur (rue, devanture de banque).

## 3. Scènes props créées (`scenes/props/`)

| Scène | Collision |
|---|---|
| `FloorTileProp.tscn` | non |
| `RugProp.tscn` | non |
| `WallSegmentProp.tscn` | StaticBody2D (rect) |
| `BankCounter.tscn` | StaticBody2D (rect) |
| `VaultDoor.tscn` | StaticBody2D (rect) |
| `SafeProp.tscn` | StaticBody2D (rect) |
| `LootBagProp.tscn` | non (visuel) |
| `DeskProp.tscn` | StaticBody2D (rect) |
| `ChairProp.tscn` | non |
| `BarrelProp.tscn` | StaticBody2D (cercle) |
| `CrateProp.tscn` | StaticBody2D (rect) |

Chaque prop = `Node2D` racine + `Sprite2D` (texture + `region_rect`) + éventuel
`StaticBody2D/CollisionShape2D` quand l'objet doit bloquer le joueur.

## 4. Comment fonctionnent les régions d'atlas

Chaque `Sprite2D` pointe sur **la planche entière** et n'affiche qu'un rectangle :

```
[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("1")        # la planche complète
region_enabled = true
region_rect = Rect2(425, 50, 235, 295)   # le coffre
```

Avantages : une seule texture chargée par planche (léger pour le web), découpage
ajustable sans réimporter d'assets.

## 5. Séparation visuel / gameplay (important)

Les props visuels **ne portent pas** la logique de jeu. Le gameplay reste dans
les scènes existantes :

- Visuel : `scenes/props/*.tscn` (Sprite2D + collision décorative éventuelle).
- Gameplay : `LootBag.tscn` (Area2D + `loot_system.gd`), `Safe.tscn`
  (Area2D + `safe.gd`), `ExitZone.tscn`, `Guard.tscn`, `Player.tscn`, etc.

Pour habiller un objet de gameplay, on lui **ajoute** un `Sprite2D` (ou on
instancie le prop visuel en enfant) sans toucher à son script ni ses signaux.

> Note d'architecture : la mission jouable (`MissionRoot.tscn`) utilise un
> **rendu isométrique procédural** (`iso_renderer.gd`) ; elle n'a pas été
> convertie aux sprites pour ne pas casser le gameplay validé. La vitrine
> `scenes/levels/BankVisualTest.tscn` démontre l'intégration des décors. La
> migration du rendu de mission vers les sprites est listée dans `TODO.md`.

## 6. Affiner / remplacer plus tard

1. **Cadrage précis** : ouvre une planche dans l'éditeur Godot, sélectionne le
   `Sprite2D` d'un prop, et ajuste `region_rect` au pixel (outil de région).
2. **TileSet** : pour le sol et les murs, créer un vrai `TileSet`
   (`assets/tilesets/`) à partir de `bank_props_sheet.png` (tuiles régulières).
3. **PNG découpés** : si tu préfères des fichiers séparés, exporte chaque objet
   dans `assets/props/` et remplace les régions par des textures simples.
4. **Collisions** : ajuster les `CollisionShape2D` aux nouvelles tailles/sprites.
