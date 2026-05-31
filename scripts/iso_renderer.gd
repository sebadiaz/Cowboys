extends Node2D
## iso_renderer.gd
## Rendu isométrique centralisé. Les entités (joueur, gardes, butin, coffre,
## sortie) restent en physique cartésienne et sont rendues INVISIBLES ; ce noeud
## lit leur position/état et dessine toute la scène en isométrique, avec tri de
## profondeur (objets "debout" du plus lointain au plus proche).

var floor_rect: Rect2
var walls: Array[Dictionary] = []     # { "rect": Rect2, "outer": bool }
var player: Node2D
var guards: Array = []
var loot: Array = []
var safe: Node = null
var exit_zone: Node = null

const FLOOR_COL := Color(0.80, 0.69, 0.49)
const FLOOR_EDGE := Color(0.6, 0.5, 0.34)
const WALL_TOP := Color(0.52, 0.38, 0.24)
const WALL_SIDE := Color(0.36, 0.26, 0.16)
const OUTER_TOP := Color(0.44, 0.30, 0.20)
const OUTER_SIDE := Color(0.30, 0.20, 0.12)


## Appelé par mission_manager après le spawn des entités.
func setup() -> void:
	# Centre le niveau dans la fenêtre.
	var vp := get_viewport_rect().size
	position = vp * 0.5 - Iso.project(floor_rect.get_center()) + Vector2(0, -20)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	_draw_floor()
	if is_instance_valid(exit_zone):
		_draw_exit()
	_draw_cones()
	# Ombres au sol (sous les objets debout).
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
			"safe": _draw_safe()
			"loot": _draw_loot(it["node"])
			"guard": _draw_guard(it["node"])
			"player": _draw_player()


# --- Sol & sortie ---

func _draw_floor() -> void:
	var poly := _rect_diamond(floor_rect)
	draw_colored_polygon(poly, FLOOR_COL)
	draw_polyline(_closed(poly), FLOOR_EDGE, 2.0)
	# Quelques lattes de plancher (lignes iso) pour le relief.
	var step := 120.0
	var x := floor_rect.position.x
	while x <= floor_rect.end.x:
		draw_line(Iso.project(Vector2(x, floor_rect.position.y)),
				Iso.project(Vector2(x, floor_rect.end.y)), FLOOR_EDGE * Color(1, 1, 1, 0.4), 1.0)
		x += step


func _draw_exit() -> void:
	var r := Rect2(exit_zone.global_position - Vector2(46, 46), Vector2(92, 92))
	var poly := _rect_diamond(r)
	draw_colored_polygon(poly, Color(0.20, 0.65, 0.25, 0.85))
	draw_polyline(_closed(poly), Color(0.15, 0.5, 0.2), 3.0)
	_text_centered("SORTIE", Iso.project(exit_zone.global_position), 16, Color(0.95, 1, 0.9))


# --- Cônes de vision (décalque au sol) ---

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


# --- Murs / coffre (boîtes iso) ---

func _draw_wall(r: Rect2, outer: bool) -> void:
	_draw_box(r, Iso.WALL_HEIGHT, OUTER_TOP if outer else WALL_TOP, OUTER_SIDE if outer else WALL_SIDE)


func _draw_safe() -> void:
	var r := Rect2(safe.global_position - Vector2(26, 20), Vector2(52, 40))
	var open: bool = safe._is_open
	var top_col := Color(0.5, 0.44, 0.28) if open else Color(0.42, 0.42, 0.46)
	var side_col := Color(0.34, 0.30, 0.18) if open else Color(0.26, 0.26, 0.30)
	_draw_box(r, 30.0, top_col, side_col)
	# Cadran sur le dessus.
	var top_center := Iso.project(safe.global_position) + Vector2(0, -30.0)
	draw_circle(top_center, 6.0, Color(0.75, 0.75, 0.2) if open else Color(0.8, 0.8, 0.85))

	# Barre de progression / invite, au-dessus du coffre.
	var head := Iso.project(safe.global_position) + Vector2(0, -56.0)
	if open:
		_text_centered("OUVERT", head, 14, Color(0.95, 0.9, 0.4))
	else:
		var prog: float = safe._progress
		if safe._player_in_range or prog > 0.0:
			var w := 56.0
			draw_rect(Rect2(head + Vector2(-w * 0.5, -4), Vector2(w, 8)), Color(0, 0, 0, 0.65))
			draw_rect(Rect2(head + Vector2(-w * 0.5, -4), Vector2(w * prog, 8)), Color(0.95, 0.8, 0.2))
			if prog <= 0.01:
				_text_centered("Maintiens E", head + Vector2(0, -10), 13, Color(1, 1, 1))


# --- Acteurs debout ---

func _draw_player() -> void:
	_draw_actor(player.global_position, 14.0, Color(0.45, 0.27, 0.13),
			Color(0.30, 0.18, 0.08), player.facing)


func _draw_guard(g: Node) -> void:
	var body := Color(0.30, 0.45, 0.85) if g.is_alert() else Color(0.20, 0.35, 0.70)
	_draw_actor(g.global_position, 14.0, body, Color(0.12, 0.20, 0.45), g.get_facing())


func _draw_loot(node: Node) -> void:
	var base := Iso.project(node.global_position)
	var lift := Vector2(0, -16.0)
	draw_circle(base + lift, 12.0, Color(0.95, 0.80, 0.15))
	draw_circle(base + lift + Vector2(0, -7.0), 6.0, Color(0.80, 0.66, 0.10))
	_text_centered("$", base + lift + Vector2(0, 5), 18, Color(0.25, 0.18, 0.0))


func _draw_actor(world_pos: Vector2, radius: float, body_col: Color, hat_col: Color, facing: Vector2) -> void:
	var base := Iso.project(world_pos)
	var center := base + Vector2(0, -radius * Iso.ACTOR_LIFT)
	# Direction de regard projetée à l'écran (pour incliner le chapeau).
	var face_screen := (Iso.project(world_pos + facing) - base)
	if face_screen.length() > 0.001:
		face_screen = face_screen.normalized()
	draw_circle(center, radius, body_col)
	draw_circle(center + Vector2(0, -radius * 0.55), radius * 0.95, hat_col)
	draw_circle(center + Vector2(0, -radius * 0.55), radius * 0.55, hat_col.lightened(0.15))
	# Repère d'orientation.
	draw_circle(center + face_screen * (radius * 0.7), 3.0, Color(0.95, 0.85, 0.55))


# --- Primitives iso ---

func _draw_box(r: Rect2, h: float, top_col: Color, side_col: Color) -> void:
	var c0 := r.position
	var c1 := Vector2(r.end.x, r.position.y)
	var c2 := r.end
	var c3 := Vector2(r.position.x, r.end.y)
	var b0 := Iso.project(c0)
	var b1 := Iso.project(c1)
	var b2 := Iso.project(c2)
	var b3 := Iso.project(c3)
	var lift := Vector2(0, -h)
	var t0 := b0 + lift
	var t1 := b1 + lift
	var t2 := b2 + lift
	var t3 := b3 + lift
	# Faces avant (les deux arêtes qui se rejoignent au coin le plus proche c2).
	draw_colored_polygon(PackedVector2Array([b1, b2, t2, t1]), side_col)
	draw_colored_polygon(PackedVector2Array([b2, b3, t3, t2]), side_col.darkened(0.08))
	# Dessus.
	draw_colored_polygon(PackedVector2Array([t0, t1, t2, t3]), top_col)
	draw_polyline(PackedVector2Array([t0, t1, t2, t3, t0]), top_col.darkened(0.25), 1.0)


func _shadow(world_pos: Vector2, radius: float) -> void:
	# Ellipse iso au sol.
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
