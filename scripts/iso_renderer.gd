extends Node2D
## iso_renderer.gd
## Rendu isométrique centralisé de la mission. Les entités restent en physique
## cartésienne (invisibles) ; ce noeud lit leur position/état et dessine la scène
## en isométrique, avec tri de profondeur. Le décor (sol, coffre, butin, props)
## utilise les TEXTURES des planches d'assets ; les personnages et les cônes de
## vision restent dessinés en formes (pas d'art de personnage dans les planches).

var floor_rect: Rect2
var walls: Array[Dictionary] = []     # { "rect": Rect2, "outer": bool }
var player: Node2D
var guards: Array = []
var loot: Array = []
var safe: Node = null
var exit_zone: Node = null

# Planches d'assets.
const SHEET_BUILD := preload("res://assets/source_sheets/bank_props_sheet.png")     # sol, murs
const SHEET_OBJ := preload("res://assets/source_sheets/bank_interior_sheet.png")    # objets
const TEX := 1254.0

# Régions (cf. assets/ASSET_INTEGRATION.md).
const R_FLOOR := Rect2(25, 25, 300, 280)
const R_SAFE := Rect2(425, 50, 235, 295)
const R_LOOT := Rect2(845, 855, 175, 205)
const R_VAULT := Rect2(50, 40, 340, 300)
const R_BARREL := Rect2(60, 635, 160, 210)
const R_CRATE := Rect2(60, 855, 180, 200)
const R_DESK := Rect2(685, 60, 290, 275)

const WALL_TOP := Color(0.52, 0.38, 0.24)
const WALL_SIDE := Color(0.36, 0.26, 0.16)
const OUTER_TOP := Color(0.44, 0.30, 0.20)
const OUTER_SIDE := Color(0.30, 0.20, 0.12)

# Décor purement visuel (sans collision), placé contre les murs.
var _decor: Array[Dictionary] = []


func setup() -> void:
	var vp := get_viewport_rect().size
	position = vp * 0.5 - Iso.project(floor_rect.get_center()) + Vector2(0, -20)
	# Props décoratifs adossés au mur du fond (n'entravent pas le jeu).
	_decor = [
		{"tex": SHEET_OBJ, "region": R_VAULT, "pos": Vector2(590, 40), "h": 122.0},
		{"tex": SHEET_OBJ, "region": R_BARREL, "pos": Vector2(120, 62), "h": 74.0},
		{"tex": SHEET_OBJ, "region": R_BARREL, "pos": Vector2(1040, 62), "h": 74.0},
		{"tex": SHEET_OBJ, "region": R_CRATE, "pos": Vector2(360, 60), "h": 70.0},
		{"tex": SHEET_OBJ, "region": R_CRATE, "pos": Vector2(820, 60), "h": 70.0},
		{"tex": SHEET_OBJ, "region": R_DESK, "pos": Vector2(210, 80), "h": 84.0},
	]
	queue_redraw()


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

	# Objets "debout" triés par profondeur (lointain -> proche).
	var items: Array[Dictionary] = []
	for w in walls:
		var c: Vector2 = w["rect"].get_center()
		items.append({"d": Iso.depth(c), "kind": "wall", "data": w})
	for d in _decor:
		items.append({"d": Iso.depth(d["pos"]), "kind": "decor", "data": d})
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
			"wall": _draw_wall(it["data"]["rect"], it["data"]["outer"])
			"decor": _draw_decor(it["data"])
			"safe": _draw_safe()
			"loot": _draw_loot(it["node"])
			"guard": _draw_guard(it["node"])
			"player": _draw_player()


# --- Sol texturé (dalles iso) ---

func _draw_floor() -> void:
	var cell := 110.0
	var y := floor_rect.position.y
	while y < floor_rect.end.y - 1.0:
		var x := floor_rect.position.x
		while x < floor_rect.end.x - 1.0:
			var w: float = min(cell, floor_rect.end.x - x)
			var h: float = min(cell, floor_rect.end.y - y)
			_floor_tile(x, y, w, h)
			x += cell
		y += cell
	# Léger contour du sol.
	draw_polyline(_closed(_rect_diamond(floor_rect)), Color(0.5, 0.4, 0.28), 2.0)


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


# --- Murs (boîtes iso) & décor texturé ---

func _draw_wall(r: Rect2, outer: bool) -> void:
	_draw_box(r, Iso.WALL_HEIGHT, OUTER_TOP if outer else WALL_TOP, OUTER_SIDE if outer else WALL_SIDE)


func _draw_decor(d: Dictionary) -> void:
	_billboard(d["tex"], d["region"], d["pos"], d["h"])


# --- Coffre & butin texturés ---

func _draw_safe() -> void:
	_billboard(SHEET_OBJ, R_SAFE, safe.global_position, 80.0)
	# Barre de progression / état, au-dessus.
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


# --- Acteurs (formes) ---

func _draw_player() -> void:
	_draw_actor(player.global_position, 14.0, Color(0.45, 0.27, 0.13),
			Color(0.30, 0.18, 0.08), player.facing)


func _draw_guard(g: Node) -> void:
	var body := Color(0.30, 0.45, 0.85) if g.is_alert() else Color(0.20, 0.35, 0.70)
	_draw_actor(g.global_position, 14.0, body, Color(0.12, 0.20, 0.45), g.get_facing())


func _draw_actor(world_pos: Vector2, radius: float, body_col: Color, hat_col: Color, facing: Vector2) -> void:
	var base := Iso.project(world_pos)
	var center := base + Vector2(0, -radius * Iso.ACTOR_LIFT)
	var face_screen := (Iso.project(world_pos + facing) - base)
	if face_screen.length() > 0.001:
		face_screen = face_screen.normalized()
	draw_circle(center, radius, body_col)
	draw_circle(center + Vector2(0, -radius * 0.55), radius * 0.95, hat_col)
	draw_circle(center + Vector2(0, -radius * 0.55), radius * 0.55, hat_col.lightened(0.15))
	draw_circle(center + face_screen * (radius * 0.7), 3.0, Color(0.95, 0.85, 0.55))


# --- Primitives ---

## Dessine une texture (région d'atlas) comme un panneau debout posé au sol.
func _billboard(tex: Texture2D, region: Rect2, world_pos: Vector2, target_h: float) -> void:
	var p := Iso.project(world_pos)
	var aspect := region.size.x / region.size.y
	var h := target_h
	var w := h * aspect
	var dest := Rect2(p.x - w * 0.5, p.y - h, w, h)
	draw_texture_rect_region(tex, dest, region)


func _draw_box(r: Rect2, h: float, top_col: Color, side_col: Color) -> void:
	var b0 := Iso.project(r.position)
	var b1 := Iso.project(Vector2(r.end.x, r.position.y))
	var b2 := Iso.project(r.end)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var lift := Vector2(0, -h)
	draw_colored_polygon(PackedVector2Array([b1, b2, b2 + lift, b1 + lift]), side_col)
	draw_colored_polygon(PackedVector2Array([b2, b3, b3 + lift, b2 + lift]), side_col.darkened(0.08))
	draw_colored_polygon(PackedVector2Array([b0 + lift, b1 + lift, b2 + lift, b3 + lift]), top_col)
	draw_polyline(PackedVector2Array([b0 + lift, b1 + lift, b2 + lift, b3 + lift, b0 + lift]), top_col.darkened(0.25), 1.0)


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
