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

var fx: Node2D = null
var _char_tex: Texture2D = null
var _billboards: Array[Dictionary] = []   # décor + comptoirs texturés
var _box_walls: Array[Dictionary] = []    # murs dessinés en boîtes 3D
var _corpses: Array[Dictionary] = []      # gardes abattus (animation de chute)


## Démarre l'animation de mort d'un garde à `world_pos`.
func add_corpse(world_pos: Vector2, facing: Vector2) -> void:
	_corpses.append({"pos": world_pos, "facing": facing, "t": 0.0})


func setup() -> void:
	if ResourceLoader.exists(CHAR_SHEET_PATH):
		_char_tex = load(CHAR_SHEET_PATH)
	_build_billboards()
	_fit_to_viewport()
	queue_redraw()


## Re-ajuste le zoom (appelé sur redimensionnement de la fenêtre). Retourne la
## position de repos pour que l'appelant resynchronise le shake/les effets.
func refit() -> Vector2:
	_fit_to_viewport()
	queue_redraw()
	return position


## Zoome et centre le niveau pour qu'il remplisse l'écran (toutes résolutions).
## On calcule la boîte englobante du niveau PROJETÉ (sol + sommets des murs +
## marge pour la hauteur des personnages), puis on choisit l'échelle qui le fait
## tenir avec une petite marge.
func _fit_to_viewport() -> void:
	var vp := get_viewport_rect().size
	var bounds := _level_screen_bounds()
	var margin := 48.0
	var avail := vp - Vector2(margin, margin) * 2.0
	var s := minf(avail.x / bounds.size.x, avail.y / bounds.size.y)
	s = clampf(s, 0.4, 3.0)
	scale = Vector2(s, s)
	# Centre la boîte englobante (en coords locales) au centre de l'écran.
	position = vp * 0.5 - bounds.get_center() * s


## Boîte englobante du niveau en coordonnées LOCALES (Iso.project, avant scale).
func _level_screen_bounds() -> Rect2:
	var pts: Array[Vector2] = []
	# Coins du sol.
	pts.append(Iso.project(floor_rect.position))
	pts.append(Iso.project(Vector2(floor_rect.end.x, floor_rect.position.y)))
	pts.append(Iso.project(floor_rect.end))
	pts.append(Iso.project(Vector2(floor_rect.position.x, floor_rect.end.y)))
	# Sommets des murs (hauteur vers le haut de l'écran).
	for w in walls:
		var r: Rect2 = w["rect"]
		var h: float = 16.0 if w.get("low", false) else Iso.WALL_HEIGHT
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			pts.append(Iso.project(c) + Vector2(0, -h))
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	# Marge verticale en haut pour la tête/chapeau des personnages (~40 px).
	mn.y -= 40.0
	return Rect2(mn, mx - mn)


func _build_billboards() -> void:
	_billboards.clear()
	_box_walls.clear()
	# Tous les murs/cloisons sont dessinés en boîtes 3D (hauteur selon type).
	for w in walls:
		var r: Rect2 = w["rect"]
		# Les cloisons intérieures basses (comptoir guichet à y~354) restent des
		# murs bas pour laisser voir par-dessus ; le reste = pleine hauteur.
		var low: bool = (not w["outer"]) and r.position.y > 340 and r.position.y < 380 and r.size.x > r.size.y
		_box_walls.append({"rect": r, "outer": w["outer"], "low": low})

	# Comptoir des guichets : meubles "BANK" posés le long de la cloison basse.
	_add_bb(SHEET_BUILD, R_COUNTER, Vector2(360, 343), 70.0)
	_add_bb(SHEET_BUILD, R_COUNTER, Vector2(745, 343), 70.0)

	# Salle des coffres : porte blindée dans l'ouverture du mur (x=820, y~290).
	_add_bb(SHEET_OBJ, R_VAULT, Vector2(832, 300), 116.0)

	# Bureau du directeur (alcôve haut-gauche) : bureau.
	_add_bb(SHEET_OBJ, R_DESK, Vector2(100, 160), 84.0)

	# Décor du hall public (bas) : tonneaux et caisses contre les murs.
	_add_bb(SHEET_OBJ, R_BARREL, Vector2(70, 560), 70.0)
	_add_bb(SHEET_OBJ, R_CRATE, Vector2(300, 595), 62.0)
	# Salle des coffres : caisse de lingots à côté du coffre (coffre = 1015,170).
	_add_bb(SHEET_OBJ, R_CRATE, Vector2(900, 250), 60.0)


func _add_bb(tex: Texture2D, region: Rect2, pos: Vector2, h: float) -> void:
	_billboards.append({"tex": tex, "region": region, "pos": pos, "h": h})


func _process(delta: float) -> void:
	# Avance et purge les corps en cours de chute (~0,7 s).
	var live: Array[Dictionary] = []
	for c in _corpses:
		c["t"] += delta
		if c["t"] < 0.7:
			live.append(c)
	_corpses = live
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
	# Corps des gardes abattus (au sol, sous les acteurs debout).
	for c in _corpses:
		_draw_corpse(c)

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
				var wh: float = 16.0 if wd.get("low", false) else Iso.WALL_HEIGHT
				_draw_box(wd["rect"], wh, wd["outer"])
			"bb":
				var d: Dictionary = it["data"]
				_billboard(d["tex"], d["region"], d["pos"], d["h"])
			"safe": _draw_safe()
			"loot": _draw_loot(it["node"])
			"guard": _draw_guard(it["node"])
			"player": _draw_player()

	_draw_bullets()
	_draw_vignette()


## Pénombre western : assombrit les bords, halo clair autour du joueur.
func _draw_vignette() -> void:
	var s: float = scale.x if scale.x > 0.001 else 1.0
	# Conversion écran -> coords locales (le noeud est zoomé).
	var vp := get_viewport_rect().size / s
	var origin := -position / s   # coin haut-gauche de l'écran en coords locales
	var band := 24.0 / s
	# Cadres semi-transparents concentriques pour assombrir les bords.
	var bands := 4
	for i in range(bands):
		var inset := float(i) * band
		var a := 0.06 * (bands - i) / bands
		var col := Color(0.05, 0.03, 0.02, a)
		# Quatre bandes (haut/bas/gauche/droite) pour ne pas réassombrir le centre.
		draw_rect(Rect2(origin.x, origin.y + inset, vp.x, band), col)
		draw_rect(Rect2(origin.x, origin.y + vp.y - inset - band, vp.x, band), col)
		draw_rect(Rect2(origin.x + inset, origin.y, band, vp.y), col)
		draw_rect(Rect2(origin.x + vp.x - inset - band, origin.y, band, vp.y), col)
	# Halo doux autour du joueur.
	if is_instance_valid(player):
		var c := Iso.project(player.global_position) + Vector2(0, -16)
		for i in range(4):
			draw_circle(c, 120.0 - i * 26.0, Color(1.0, 0.93, 0.7, 0.04))


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
	_draw_person(player.global_position, player.facing, pal, false, false,
			player.walk_phase, player.recoil, 0.0)


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
	var flash: float = g.hit_flash if "hit_flash" in g else 0.0
	_draw_person(g.global_position, g.get_facing(), pal, true, alert,
			_wphase(g), 0.0, flash)


func _wphase(g: Node) -> float:
	# Phase de marche dérivée de la vitesse (pas d'état stocké côté garde).
	return (Time.get_ticks_msec() * 0.012) if (("velocity" in g) and g.velocity.length() > 5.0) else 0.0


## Personnage "debout" vu en iso : ombre, jambes (animées), torse, bras + pistolet
## (recul), tête et chapeau. `flash` blanchit le corps quand touché.
func _draw_person(world_pos: Vector2, facing: Vector2, pal: Dictionary, is_guard: bool,
		alert: bool, walk: float, recoil: float, flash: float) -> void:
	var base := Iso.project(world_pos)
	var f := Iso.project(world_pos + facing) - base
	if f.length() > 0.001:
		f = f.normalized()
	var side := signf(f.x) if absf(f.x) > 0.15 else 1.0
	var facing_up := f.y < -0.25

	# Teinte (flash blanc quand touché).
	var shirt: Color = pal["shirt"].lerp(Color.WHITE, flash * 0.7)
	var vest: Color = pal["vest"].lerp(Color.WHITE, flash * 0.7)

	# Ombre au sol.
	draw_colored_polygon(_ellipse(base, 13.0, 6.0), Color(0, 0, 0, 0.22))

	# Balancement de marche.
	var sw := sin(walk) * 3.0
	var bob := absf(sin(walk)) * -1.5
	var hip := base + Vector2(0, -16.0 + bob)
	var shoulder := base + Vector2(0, -30.0 + bob)

	# Jambes (alternées).
	draw_line(hip + Vector2(-4, 0), base + Vector2(-5 - sw, -1), pal["pants"], 5.0)
	draw_line(hip + Vector2(4, 0), base + Vector2(5 + sw, -1), pal["pants"], 5.0)
	draw_circle(base + Vector2(-5 - sw, -1), 2.6, Color(0.18, 0.12, 0.08))
	draw_circle(base + Vector2(5 + sw, -1), 2.6, Color(0.18, 0.12, 0.08))

	# Torse + gilet.
	_draw_capsule(hip, shoulder, 9.0, shirt)
	_draw_capsule(hip + Vector2(0, -2), shoulder, 6.0, vest)
	if is_guard:
		draw_circle(shoulder + Vector2(-3.0 * side, 6.0), 2.6,
				Color(1.0, 0.9, 0.3) if alert else Color(0.85, 0.78, 0.3))

	# Bras + pistolet (recul = bras ramené vers l'épaule).
	var gun_dir := Vector2(side, -0.15 if not facing_up else -0.5).normalized()
	var reach := 13.0 - recoil * 4.0
	var hand := shoulder + gun_dir * reach + Vector2(0, 4)
	draw_line(shoulder + Vector2(-side * 4, 2), shoulder + Vector2(-side * 7, 7), shirt.darkened(0.1), 4.0)
	draw_line(shoulder + Vector2(side * 3, 3), hand, shirt, 4.0)
	draw_line(hand, hand + gun_dir * 7.0, Color(0.15, 0.15, 0.17), 3.0)
	draw_line(hand, hand + Vector2(0, 4), Color(0.10, 0.10, 0.12), 3.0)

	# Tête + chapeau.
	var head := shoulder + Vector2(0, -7.0)
	draw_circle(head, 5.5, pal["skin"])
	draw_colored_polygon(_ellipse(head + Vector2(0, -3.0), 11.0, 3.4), pal["hat"])
	draw_colored_polygon(_ellipse(head + Vector2(0, -6.0), 5.0, 4.5), pal["hat"].darkened(0.1))
	draw_line(head + Vector2(-9, -3), head + Vector2(9, -3), pal["hat"].lightened(0.15), 1.5)


## Garde abattu : bascule au sol + fondu.
func _draw_corpse(c: Dictionary) -> void:
	var t: float = clampf(c["t"] / 0.7, 0.0, 1.0)
	var base := Iso.project(c["pos"])
	var a := (1.0 - t) * 0.9
	# S'aplatit progressivement en une silhouette couchée.
	var fall := lerpf(0.0, 10.0, t)
	draw_colored_polygon(_ellipse(base, 13.0 + fall, 6.0 + fall * 0.4), Color(0, 0, 0, 0.18 * (1.0 - t)))
	var col := Color(0.22, 0.34, 0.66, a)
	draw_colored_polygon(_ellipse(base + Vector2(0, -4 + fall * 0.3), 9.0 + fall, 5.0), col)
	# Tête qui roule légèrement.
	draw_circle(base + Vector2((6.0 + fall) * signf(c["facing"].x if c["facing"].x != 0 else 1), -2),
			4.0, Color(0.84, 0.64, 0.46, a))


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
