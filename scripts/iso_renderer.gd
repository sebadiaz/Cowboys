extends Node2D
## iso_renderer.gd
## Rendu isométrique centralisé de la mission. Les entités restent en physique
## cartésienne (invisibles) ; ce noeud lit leur position/état et dessine la scène
## en isométrique avec tri de profondeur. Le décor utilise les TEXTURES des
## planches (régions d'atlas). Les personnages utilisent une planche optionnelle
## (characters_sheet.png) si présente, sinon un rendu en formes.

var floor_rect: Rect2
var walls: Array[Dictionary] = []     # { "rect": Rect2, "outer": bool }
var player: Node2D
var guards: Array = []
var loot: Array = []
var safe: Node = null
var exit_zone: Node = null
var bullets: Node = null

# Planches d'assets.
const SHEET_BUILD := preload("res://assets/source_sheets/bank_props_sheet.png")     # sol, murs, comptoir
const SHEET_OBJ := preload("res://assets/source_sheets/bank_interior_sheet.png")    # objets
const TEX := 1254.0
# Planche de personnages OPTIONNELLE (déposer ce fichier pour l'activer).
const CHAR_SHEET_PATH := "res://assets/source_sheets/characters_sheet.png"

# Régions (cf. assets/ASSET_INTEGRATION.md).
const R_FLOOR := Rect2(58, 58, 236, 214)   # recadré à l'intérieur de la dalle (sans bordure)
const R_WALL := Rect2(395, 350, 215, 175)
const R_COUNTER := Rect2(25, 770, 620, 190)
const R_SAFE := Rect2(425, 50, 235, 295)
const R_LOOT := Rect2(845, 855, 175, 205)
const R_VAULT := Rect2(50, 40, 340, 300)
const R_BARREL := Rect2(60, 635, 160, 210)
const R_CRATE := Rect2(60, 855, 180, 200)
const R_DESK := Rect2(685, 60, 290, 275)
# Personnages (planche optionnelle, grille 128 px par défaut).
const R_PLAYER := Rect2(0, 0, 128, 128)
const R_GUARD := Rect2(128, 0, 128, 128)

var _char_tex: Texture2D = null
var _billboards: Array[Dictionary] = []   # décor + comptoirs texturés
var _box_walls: Array[Dictionary] = []    # murs dessinés en boîtes 3D


func setup() -> void:
	var vp := get_viewport_rect().size
	position = vp * 0.5 - Iso.project(floor_rect.get_center()) + Vector2(0, -20)
	if ResourceLoader.exists(CHAR_SHEET_PATH):
		_char_tex = load(CHAR_SHEET_PATH)
	_build_billboards()
	queue_redraw()


func _build_billboards() -> void:
	_billboards.clear()
	_box_walls.clear()
	# Murs : boîtes 3D, sauf le long obstacle intérieur horizontal -> comptoir.
	for w in walls:
		var r: Rect2 = w["rect"]
		var outer: bool = w["outer"]
		if not outer and r.size.x >= 150.0 and r.size.x >= r.size.y:
			_add_bb(SHEET_BUILD, R_COUNTER, r.get_center(), 78.0)
		else:
			_box_walls.append(w)
	# Props décoratifs adossés au mur du fond (sans collision).
	_add_bb(SHEET_OBJ, R_VAULT, Vector2(590, 44), 120.0)
	_add_bb(SHEET_OBJ, R_BARREL, Vector2(120, 64), 74.0)
	_add_bb(SHEET_OBJ, R_BARREL, Vector2(1040, 64), 74.0)
	_add_bb(SHEET_OBJ, R_CRATE, Vector2(300, 62), 70.0)
	_add_bb(SHEET_OBJ, R_DESK, Vector2(210, 90), 84.0)


func _add_bb(tex: Texture2D, region: Rect2, pos: Vector2, h: float) -> void:
	_billboards.append({"tex": tex, "region": region, "pos": pos, "h": h})


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	_draw_floor()
	if is_instance_valid(exit_zone):
		_draw_exit()
	_draw_cones()
	if is_instance_valid(player):
		_shadow(player.global_position, 14.0)
	for g in guards:
		if is_instance_valid(g):
			_shadow(g.global_position, 14.0)
	for b in loot:
		if is_instance_valid(b):
			_shadow(b.global_position, 11.0)

	# Tout ce qui est "debout", trié par profondeur (lointain -> proche).
	var items: Array[Dictionary] = []
	for w in _box_walls:
		items.append({"d": Iso.depth(w["rect"].get_center()), "kind": "wall", "data": w})
	for bb in _billboards:
		items.append({"d": Iso.depth(bb["pos"]), "kind": "bb", "data": bb})
	if is_instance_valid(safe):
		items.append({"d": Iso.depth(safe.global_position), "kind": "safe"})
	for b in loot:
		if is_instance_valid(b):
			items.append({"d": Iso.depth(b.global_position), "kind": "loot", "node": b})
	for g in guards:
		if is_instance_valid(g):
			items.append({"d": Iso.depth(g.global_position), "kind": "guard", "node": g})
	if is_instance_valid(player):
		items.append({"d": Iso.depth(player.global_position), "kind": "player"})

	items.sort_custom(func(a, b): return a["d"] < b["d"])
	for it in items:
		match it["kind"]:
			"wall":
				var wd: Dictionary = it["data"]
				_draw_box(wd["rect"], Iso.WALL_HEIGHT, wd["outer"])
			"bb":
				var d: Dictionary = it["data"]
				_billboard(d["tex"], d["region"], d["pos"], d["h"])
			"safe": _draw_safe()
			"loot": _draw_loot(it["node"])
			"guard": _draw_guard(it["node"])
			"player": _draw_player()

	_draw_bullets()


func _draw_bullets() -> void:
	if bullets == null:
		return
	for b in bullets.bullets:
		var p: Vector2 = Iso.project(b["pos"]) + Vector2(0, -16.0)
		var col := Color(1.0, 0.9, 0.3) if b["friendly"] else Color(1.0, 0.4, 0.2)
		draw_circle(p, 4.5, Color(0, 0, 0, 0.3))
		draw_circle(p, 3.5, col)


# --- Sol texturé (dalles iso) ---

func _draw_floor() -> void:
	var cell := 132.0
	var y := floor_rect.position.y
	while y < floor_rect.end.y - 1.0:
		var x := floor_rect.position.x
		while x < floor_rect.end.x - 1.0:
			var w: float = min(cell, floor_rect.end.x - x)
			var h: float = min(cell, floor_rect.end.y - y)
			_floor_tile(x, y, w, h)
			x += cell
		y += cell
	draw_polyline(_closed(_rect_diamond(floor_rect)), Color(0.45, 0.34, 0.22), 2.0)


func _floor_tile(x: float, y: float, w: float, h: float) -> void:
	var pts := PackedVector2Array([
		Iso.project(Vector2(x, y)),
		Iso.project(Vector2(x + w, y)),
		Iso.project(Vector2(x + w, y + h)),
		Iso.project(Vector2(x, y + h)),
	])
	var p := R_FLOOR.position
	var s := R_FLOOR.size
	var uvs := PackedVector2Array([
		p / TEX,
		Vector2(p.x + s.x, p.y) / TEX,
		Vector2(p.x + s.x, p.y + s.y) / TEX,
		Vector2(p.x, p.y + s.y) / TEX,
	])
	draw_colored_polygon(pts, Color.WHITE, uvs, SHEET_BUILD)


func _draw_exit() -> void:
	var r := Rect2(exit_zone.global_position - Vector2(46, 46), Vector2(92, 92))
	var poly := _rect_diamond(r)
	draw_colored_polygon(poly, Color(0.20, 0.65, 0.25, 0.85))
	draw_polyline(_closed(poly), Color(0.15, 0.5, 0.2), 3.0)
	_text_centered("SORTIE", Iso.project(exit_zone.global_position), 16, Color(0.95, 1, 0.9))


# --- Cônes de vision ---

func _draw_cones() -> void:
	for g in guards:
		if not is_instance_valid(g):
			continue
		var apex: Vector2 = g.global_position
		var facing: Vector2 = g.get_facing()
		if facing.length() < 0.01:
			facing = Vector2.DOWN
		var dist: float = g.get_view_distance()
		var half: float = g.get_view_half_angle()
		var base_angle := facing.angle()
		var pts := PackedVector2Array()
		pts.append(Iso.project(apex))
		var steps := 16
		for i in range(steps + 1):
			var a: float = base_angle - half + (2.0 * half) * float(i) / float(steps)
			pts.append(Iso.project(apex + Vector2.RIGHT.rotated(a) * dist))
		var fill: Color
		if g.is_alert():
			fill = Color(1.0, 0.15, 0.15, 0.28)
		elif g.get_alert_ratio() > 0.05:
			fill = Color(1.0, 0.55, 0.0, 0.24)
		else:
			fill = Color(1.0, 1.0, 0.0, 0.16)
		draw_colored_polygon(pts, fill)


# --- Coffre & butin texturés ---

func _draw_safe() -> void:
	_billboard(SHEET_OBJ, R_SAFE, safe.global_position, 80.0)
	var head := Iso.project(safe.global_position) + Vector2(0, -86.0)
	if safe._is_open:
		_text_centered("OUVERT", head, 14, Color(0.95, 0.9, 0.4))
	else:
		var prog: float = safe._progress
		if safe._player_in_range or prog > 0.0:
			var w := 60.0
			draw_rect(Rect2(head + Vector2(-w * 0.5, -4), Vector2(w, 8)), Color(0, 0, 0, 0.65))
			draw_rect(Rect2(head + Vector2(-w * 0.5, -4), Vector2(w * prog, 8)), Color(0.95, 0.8, 0.2))
			if prog <= 0.01:
				_text_centered("Maintiens E", head + Vector2(0, -10), 13, Color(1, 1, 1))


func _draw_loot(node: Node) -> void:
	_billboard(SHEET_OBJ, R_LOOT, node.global_position, 52.0)


# --- Acteurs (planche personnages si présente, sinon formes) ---

func _draw_player() -> void:
	if _char_tex != null:
		_billboard(_char_tex, R_PLAYER, player.global_position, 56.0)
		return
	var pal := {
		"hat": Color(0.40, 0.26, 0.13), "shirt": Color(0.74, 0.30, 0.20),
		"vest": Color(0.45, 0.30, 0.16), "pants": Color(0.28, 0.22, 0.16),
		"skin": Color(0.86, 0.66, 0.48),
	}
	_draw_person(player.global_position, player.facing, pal, false, false)


func _draw_guard(g: Node) -> void:
	if _char_tex != null:
		_billboard(_char_tex, R_GUARD, g.global_position, 56.0, g.is_alert())
		return
	var alert: bool = g.is_alert()
	var pal := {
		"hat": Color(0.12, 0.18, 0.40),
		"shirt": Color(0.30, 0.42, 0.82) if alert else Color(0.22, 0.34, 0.66),
		"vest": Color(0.16, 0.24, 0.50), "pants": Color(0.16, 0.18, 0.26),
		"skin": Color(0.84, 0.64, 0.46),
	}
	_draw_person(g.global_position, g.get_facing(), pal, true, alert)


## Personnage "debout" vu en iso : ombre, jambes, torse, bras + pistolet,
## tête et chapeau de cowboy. `facing` oriente le corps et l'arme.
func _draw_person(world_pos: Vector2, facing: Vector2, pal: Dictionary, is_guard: bool, alert: bool) -> void:
	var base := Iso.project(world_pos)
	# Direction projetée à l'écran (gauche/droite) pour orienter l'arme.
	var f := Iso.project(world_pos + facing) - base
	if f.length() > 0.001:
		f = f.normalized()
	var side := signf(f.x) if absf(f.x) > 0.15 else 1.0
	var facing_up := f.y < -0.25

	# Ombre au sol.
	draw_colored_polygon(_ellipse(base, 13.0, 6.0), Color(0, 0, 0, 0.22))

	var hip := base + Vector2(0, -16.0)
	var shoulder := base + Vector2(0, -30.0)

	# Jambes.
	draw_line(hip + Vector2(-4, 0), base + Vector2(-5, -1), pal["pants"], 5.0)
	draw_line(hip + Vector2(4, 0), base + Vector2(5, -1), pal["pants"], 5.0)
	# Bottes.
	draw_circle(base + Vector2(-5, -1), 2.6, Color(0.18, 0.12, 0.08))
	draw_circle(base + Vector2(5, -1), 2.6, Color(0.18, 0.12, 0.08))

	# Torse (chemise) + gilet.
	_draw_capsule(hip, shoulder, 9.0, pal["shirt"])
	_draw_capsule(hip + Vector2(0, -2), shoulder, 6.0, pal["vest"])
	if is_guard:
		# Étoile de shérif.
		draw_circle(shoulder + Vector2(-3.0 * side, 6.0), 2.6,
				Color(1.0, 0.9, 0.3) if alert else Color(0.85, 0.78, 0.3))

	# Bras arrière + bras qui tient le pistolet (vers facing).
	var gun_dir := Vector2(side, -0.15 if not facing_up else -0.5).normalized()
	var hand := shoulder + gun_dir * 13.0 + Vector2(0, 4)
	draw_line(shoulder + Vector2(-side * 4, 2), shoulder + Vector2(-side * 7, 7), pal["shirt"].darkened(0.1), 4.0)
	draw_line(shoulder + Vector2(side * 3, 3), hand, pal["shirt"], 4.0)
	# Pistolet.
	draw_line(hand, hand + gun_dir * 7.0, Color(0.15, 0.15, 0.17), 3.0)
	draw_line(hand, hand + Vector2(0, 4), Color(0.10, 0.10, 0.12), 3.0)

	# Tête + chapeau de cowboy (couronne + bord).
	var head := shoulder + Vector2(0, -7.0)
	draw_circle(head, 5.5, pal["skin"])
	draw_colored_polygon(_ellipse(head + Vector2(0, -3.0), 11.0, 3.4), pal["hat"])      # bord
	draw_colored_polygon(_ellipse(head + Vector2(0, -6.0), 5.0, 4.5), pal["hat"].darkened(0.1))  # couronne
	draw_line(head + Vector2(-9, -3), head + Vector2(9, -3), pal["hat"].lightened(0.15), 1.5)


func _draw_capsule(a: Vector2, b: Vector2, width: float, col: Color) -> void:
	draw_line(a, b, col, width)
	draw_circle(a, width * 0.5, col)
	draw_circle(b, width * 0.5, col)


func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(18):
		var t := TAU * float(i) / 18.0
		pts.append(center + Vector2(cos(t) * rx, sin(t) * ry))
	return pts


# --- Primitives ---

## Mur en boîte 3D iso : faces latérales colorées + dessus texturé bois.
func _draw_box(r: Rect2, h: float, outer: bool) -> void:
	var side_col := Color(0.30, 0.20, 0.12) if outer else Color(0.36, 0.26, 0.16)
	var b0 := Iso.project(r.position)
	var b1 := Iso.project(Vector2(r.end.x, r.position.y))
	var b2 := Iso.project(r.end)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var lift := Vector2(0, -h)
	draw_colored_polygon(PackedVector2Array([b1, b2, b2 + lift, b1 + lift]), side_col)
	draw_colored_polygon(PackedVector2Array([b2, b3, b3 + lift, b2 + lift]), side_col.darkened(0.08))
	var top := PackedVector2Array([b0 + lift, b1 + lift, b2 + lift, b3 + lift])
	var p := R_FLOOR.position
	var s := R_FLOOR.size
	var uvs := PackedVector2Array([
		p / TEX, Vector2(p.x + s.x, p.y) / TEX,
		Vector2(p.x + s.x, p.y + s.y) / TEX, Vector2(p.x, p.y + s.y) / TEX,
	])
	var top_mod := Color(0.82, 0.70, 0.50) if outer else Color(0.95, 0.85, 0.70)
	draw_colored_polygon(top, top_mod, uvs, SHEET_BUILD)
	draw_polyline(_closed(top), side_col.darkened(0.2), 1.0)


## Texture (région d'atlas) dessinée comme un panneau debout posé au sol.
func _billboard(tex: Texture2D, region: Rect2, world_pos: Vector2, target_h: float, alert := false) -> void:
	var p := Iso.project(world_pos)
	var aspect := region.size.x / region.size.y
	var h := target_h
	var w := h * aspect
	var dest := Rect2(p.x - w * 0.5, p.y - h, w, h)
	var mod := Color(1, 0.85, 0.85) if alert else Color.WHITE
	draw_texture_rect_region(tex, dest, region, mod)


func _shadow(world_pos: Vector2, radius: float) -> void:
	var c := Iso.project(world_pos)
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		pts.append(c + Vector2(cos(a) * radius * 1.2, sin(a) * radius * Iso.H * 1.2))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.22))


func _rect_diamond(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		Iso.project(r.position),
		Iso.project(Vector2(r.end.x, r.position.y)),
		Iso.project(r.end),
		Iso.project(Vector2(r.position.x, r.end.y)),
	])


func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var p := poly.duplicate()
	if p.size() > 0:
		p.append(p[0])
	return p


func _text_centered(text: String, pos: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
