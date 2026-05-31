extends Node2D
## bank_visual_test.gd
## Scène vitrine (décor seulement) : compose une banque western 2D / 2.5D à
## partir des scènes props (Sprite2D + régions d'atlas). Ne contient pas de
## gameplay — la mission jouable reste MissionRoot.tscn. Tri de profondeur par
## y-sort pour un rendu 2.5D (les objets plus bas passent devant).

const FloorTile := preload("res://scenes/props/FloorTileProp.tscn")
const Wall := preload("res://scenes/props/WallSegmentProp.tscn")
const Rug := preload("res://scenes/props/RugProp.tscn")
const Counter := preload("res://scenes/props/BankCounter.tscn")
const Vault := preload("res://scenes/props/VaultDoor.tscn")
const SafeP := preload("res://scenes/props/SafeProp.tscn")
const Desk := preload("res://scenes/props/DeskProp.tscn")
const Chair := preload("res://scenes/props/ChairProp.tscn")
const Barrel := preload("res://scenes/props/BarrelProp.tscn")
const Crate := preload("res://scenes/props/CrateProp.tscn")
const LootBag := preload("res://scenes/props/LootBagProp.tscn")

const T := 128.0
const COLS := 9
const ROWS := 7

var _floor: Node2D
var _props: Node2D


func _ready() -> void:
	_floor = Node2D.new()
	_floor.name = "Floor"
	_floor.z_index = -10
	add_child(_floor)

	_props = Node2D.new()
	_props.name = "Props"
	_props.y_sort_enabled = true  # rendu 2.5D : tri par position Y
	add_child(_props)

	_build_floor()
	_build_walls()
	_build_furniture()
	_build_title()


func _cell(c: float, r: float) -> Vector2:
	return Vector2(c * T, r * T)


func _put(scene: PackedScene, c: float, r: float, parent: Node2D, scale := 1.0) -> Node2D:
	var n: Node2D = scene.instantiate()
	n.position = _cell(c, r)
	if scale != 1.0:
		n.scale = Vector2(scale, scale)
	parent.add_child(n)
	return n


func _build_floor() -> void:
	for r in range(ROWS):
		for c in range(COLS):
			_put(FloorTile, c, r, _floor)
	# Tapis central (au-dessus du sol, sous les meubles).
	var rug := _put(Rug, 4, 3, _floor, 1.6)
	rug.z_index = -5


func _build_walls() -> void:
	for c in range(COLS):
		_put(Wall, c, 0, _props)
		_put(Wall, c, ROWS - 1, _props)
	for r in range(1, ROWS - 1):
		_put(Wall, 0, r, _props)
		_put(Wall, COLS - 1, r, _props)
	# Porte de coffre encastrée dans le mur du fond.
	_put(Vault, 4, 0, _props)


func _build_furniture() -> void:
	# Coffre près de la porte de coffre.
	_put(SafeP, 6, 1, _props)
	# Comptoir de banque (rangée).
	_put(Counter, 3, 4, _props)
	_put(Counter, 4, 4, _props)
	_put(Counter, 5, 4, _props)
	# Bureau + chaise.
	_put(Desk, 2, 2, _props)
	_put(Chair, 2, 2.9, _props)
	# Barils et caisses dans les coins.
	_put(Barrel, 1, 1, _props)
	_put(Barrel, 7, 5, _props)
	_put(Crate, 1, 5, _props)
	_put(Crate, 7, 1, _props)
	# Sacs de butin (décor).
	_put(LootBag, 4, 2, _props, 0.7)
	_put(LootBag, 6, 4, _props, 0.7)
	_put(LootBag, 2, 5, _props, 0.7)
	# Sortie visible (marqueur + label).
	_build_exit(4, ROWS - 1)


func _build_exit(c: float, r: float) -> void:
	var marker := ColorRect.new()
	marker.color = Color(0.20, 0.65, 0.25, 0.9)
	marker.size = Vector2(120, 70)
	marker.position = _cell(c, r) - marker.size * 0.5
	marker.z_index = 50
	_props.add_child(marker)
	var lbl := Label.new()
	lbl.text = "SORTIE"
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.95, 1, 0.9))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = _cell(c, r) + Vector2(-40, -16)
	lbl.z_index = 51
	_props.add_child(lbl)


func _build_title() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var lbl := Label.new()
	lbl.text = "BankVisualTest — décor banque western (placeholders)"
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = Vector2(16, 12)
	layer.add_child(lbl)
