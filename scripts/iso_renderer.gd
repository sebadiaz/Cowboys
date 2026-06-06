extends Node2D
## iso_renderer.gd
## Rendu isométrique centralisé de la mission. Les entités restent en physique
## cartésienne (invisibles) ; ce noeud lit leur position/état et dessine la scène
## en isométrique avec tri de profondeur. Le décor utilise les TEXTURES des
## planches (régions d'atlas). Les personnages utilisent une planche optionnelle
## (characters_sheet.png) si présente, sinon un rendu en formes.

var floor_rect: Rect2
var walls: Array[Dictionary] = []     # { "rect": Rect2, "outer": bool, "low": bool }
var props: Array = []                 # [ ["type", x, y, h?], ... ] depuis les données
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


var _cam_pos := Vector2.ZERO   # position de caméra lissée (sans le shake)


func setup() -> void:
	if ResourceLoader.exists(CHAR_SHEET_PATH):
		_char_tex = load(CHAR_SHEET_PATH)
	_build_billboards()
	_apply_zoom()
	_cam_pos = _camera_target()
	position = _cam_pos
	queue_redraw()


## Recalcule le zoom (sur redimensionnement de la fenêtre / rotation mobile).
func refit() -> Vector2:
	_apply_zoom()
	_cam_pos = _camera_target()
	position = _cam_pos
	queue_redraw()
	return _cam_pos


## Choisit un zoom RAPPROCHÉ pour que le cowboy et l'action soient bien gros.
## Basé sur la plus petite dimension de l'écran (marche en paysage et portrait).
func _apply_zoom() -> void:
	var vp := get_viewport_rect().size
	var z := clampf(minf(vp.x, vp.y) / 360.0, 1.8, 3.6)
	scale = Vector2(z, z)


## Position de caméra cible : centre le joueur, bornée à l'emprise du niveau
## pour ne pas montrer le vide au-delà des murs.
func _camera_target() -> Vector2:
	var vp := get_viewport_rect().size
	var s: float = scale.x
	var b := _level_screen_bounds()
	var focus := Vector2.ZERO
	if is_instance_valid(player):
		focus = Iso.project(player.global_position) + Vector2(0, -16)
	else:
		focus = b.get_center()
	var t := vp * 0.5 - focus * s
	t.x = _clamp_axis(t.x, s, vp.x, b.position.x, b.end.x)
	t.y = _clamp_axis(t.y, s, vp.y, b.position.y, b.end.y)
	return t


## Borne un axe de caméra : garde l'écran à l'intérieur du niveau, ou centre si
## le niveau est plus petit que l'écran sur cet axe.
func _clamp_axis(t: float, s: float, screen: float, bmin: float, bmax: float) -> float:
	var lo := screen - s * bmax   # pour que le bord droit/bas du niveau >= écran
	var hi := -s * bmin           # pour que le bord gauche/haut du niveau <= 0
	if lo > hi:
		return screen * 0.5 - s * (bmin + bmax) * 0.5   # niveau plus petit : centré
	return clampf(t, lo, hi)


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


## Table des props : type -> [planche, région, hauteur par défaut].
func _prop_def(t: String) -> Array:
	match t:
		"counter": return [SHEET_BUILD, R_COUNTER, 70.0]
		"vault": return [SHEET_OBJ, R_VAULT, 116.0]
		"desk": return [SHEET_OBJ, R_DESK, 82.0]
		"barrel": return [SHEET_OBJ, R_BARREL, 70.0]
		"crate": return [SHEET_OBJ, R_CRATE, 60.0]
		_: return []


func _build_billboards() -> void:
	_billboards.clear()
	_box_walls.clear()
	# Murs/cloisons dessinés en boîtes 3D (hauteur selon le drapeau "low").
	for w in walls:
		_box_walls.append({"rect": w["rect"], "outer": w["outer"], "low": w.get("low", false)})

	# Props décoratifs pilotés par les données du niveau.
	for p in props:
		if not (p is Array) or p.size() < 3:
			continue
		var def := _prop_def(str(p[0]))
		if def.is_empty():
			continue
		var pos := Vector2(float(p[1]), float(p[2]))
		var h: float = float(p[3]) if p.size() > 3 else float(def[2])
		_add_bb(def[0], def[1], pos, h)


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
	# Caméra : suit le joueur en douceur, plus le screen-shake.
	_cam_pos = _cam_pos.lerp(_camera_target(), clampf(delta * 8.0, 0.0, 1.0))
	var shake := Vector2.ZERO
	if fx != null and fx.has_method("get_shake_offset"):
		shake = fx.get_shake_offset()
	position = _cam_pos + shake
	queue_redraw()


func _draw() -> void:
	Iso.yaw = 0.0          # la mission se joue toujours en vue iso fixe
	_draw_floor()
	_draw_decor()
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
	_draw_objective_arrow()
	_draw_vignette()


## Flèche d'objectif au-dessus du joueur : pointe vers le butin le plus proche,
## sinon le coffre, sinon la sortie. Rend l'objectif évident.
func _draw_objective_arrow() -> void:
	if not is_instance_valid(player):
		return
	var target := Vector2.ZERO
	var label := ""
	# Butin restant le plus proche ?
	var best := INF
	for b in loot:
		if is_instance_valid(b):
			var d: float = player.global_position.distance_to(b.global_position)
			if d < best:
				best = d
				target = b.global_position
				label = "BUTIN"
	if label == "" and is_instance_valid(safe) and not safe._is_open:
		target = safe.global_position
		label = "COFFRE"
	if label == "" and is_instance_valid(exit_zone):
		target = exit_zone.global_position
		label = "SORTIE"
	if label == "":
		return
	var pp := Iso.project(player.global_position) + Vector2(0, -44)
	var dir := (Iso.project(target) - Iso.project(player.global_position))
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var bob := sin(Time.get_ticks_msec() * 0.006) * 3.0
	var c := pp + dir * (14.0 + bob)
	var perp := dir.orthogonal()
	# Chevron pointant vers la cible.
	draw_colored_polygon(PackedVector2Array([
		c + dir * 9.0, c - dir * 4.0 + perp * 7.0, c - dir * 4.0 - perp * 7.0]),
		Color(1.0, 0.85, 0.25))
	_text_centered("» %s »" % label, pp + Vector2(0, -10), 12, Color(1.0, 0.92, 0.6))


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


# --- Décor au sol (tapis) + lampes d'ambiance ---

## Tapis western et lampes : posés à plat sur le sol (sous les acteurs/props).
## Générique : s'adapte à la taille du niveau et à la position du coffre.
func _draw_decor() -> void:
	# Tapis prestige devant le coffre.
	if is_instance_valid(safe):
		_rug(safe.global_position + Vector2(0, 90), 150, 150,
				Color(0.55, 0.14, 0.12), Color(0.85, 0.68, 0.25))
	# Grand tapis au centre du niveau (sous le lustre).
	_rug(floor_rect.get_center(), 230, 200, Color(0.40, 0.20, 0.30), Color(0.80, 0.62, 0.30))
	# Lampes d'ambiance réparties le long du bord haut du niveau + côtés.
	var fr := floor_rect
	var n := maxi(3, int(fr.size.x / 360.0))
	for i in range(n + 1):
		_lamp(Vector2(lerpf(fr.position.x + 60.0, fr.end.x - 60.0, float(i) / n), fr.position.y + 8.0))
	_lamp(Vector2(fr.position.x + 8.0, fr.get_center().y))
	_lamp(Vector2(fr.end.x - 8.0, fr.get_center().y))


func _rug(center: Vector2, w: float, h: float, col: Color, accent: Color) -> void:
	var r := Rect2(center - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	var poly := _rect_diamond(r)
	draw_colored_polygon(poly, col)
	draw_polyline(_closed(poly), accent, 2.5)
	var inner := Rect2(center - Vector2(w * 0.32, h * 0.32), Vector2(w * 0.64, h * 0.64))
	draw_polyline(_closed(_rect_diamond(inner)), accent.darkened(0.1), 1.5)


func _lamp(world_pos: Vector2) -> void:
	var p := Iso.project(world_pos)
	# Halo lumineux chaud (plusieurs cercles dégradés).
	for i in range(4):
		draw_circle(p + Vector2(0, -6), 26.0 - i * 6.0, Color(1.0, 0.85, 0.45, 0.06))
	draw_circle(p + Vector2(0, -6), 4.0, Color(1.0, 0.92, 0.6, 0.9))


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
	# Cowboy "héros" : duster fauve, chemise rouille, bandana rouge, chapeau clair.
	var pal := {
		"hat": Color(0.74, 0.62, 0.42), "hat_band": Color(0.55, 0.16, 0.12),
		"coat": Color(0.55, 0.36, 0.18), "coat_dark": Color(0.42, 0.27, 0.13),
		"shirt": Color(0.82, 0.46, 0.20), "pants": Color(0.32, 0.26, 0.20),
		"skin": Color(0.90, 0.69, 0.50), "bandana": Color(0.86, 0.22, 0.18),
		"belt": Color(0.26, 0.16, 0.09), "buckle": Color(0.95, 0.80, 0.32),
		"boots": Color(0.30, 0.18, 0.10), "hair": Color(0.25, 0.16, 0.09),
	}
	_draw_person(player.global_position, player.facing, pal, false, false,
			player.walk_phase, player.recoil, 0.0)


func _draw_guard(g: Node) -> void:
	if _char_tex != null:
		_billboard(_char_tex, R_GUARD, g.global_position, 56.0, g.is_alert())
		return
	var alert: bool = g.is_alert()
	# Garde/shérif : long manteau bleu, étoile, plus terne que le héros.
	var pal := {
		"hat": Color(0.16, 0.20, 0.38), "hat_band": Color(0.09, 0.11, 0.22),
		"coat": Color(0.24, 0.34, 0.66) if alert else Color(0.19, 0.27, 0.52),
		"coat_dark": Color(0.14, 0.21, 0.42),
		"shirt": Color(0.30, 0.42, 0.78) if alert else Color(0.24, 0.34, 0.62),
		"pants": Color(0.15, 0.17, 0.26),
		"skin": Color(0.84, 0.64, 0.46), "bandana": Color(0.40, 0.50, 0.82),
		"belt": Color(0.12, 0.13, 0.18), "buckle": Color(0.82, 0.84, 0.88),
		"boots": Color(0.12, 0.13, 0.18), "hair": Color(0.16, 0.14, 0.12),
	}
	var flash: float = g.hit_flash if "hit_flash" in g else 0.0
	_draw_person(g.global_position, g.get_facing(), pal, true, alert,
			_wphase(g), 0.0, flash)


func _wphase(g: Node) -> float:
	# Phase de marche dérivée de la vitesse (pas d'état stocké côté garde).
	return (Time.get_ticks_msec() * 0.012) if (("velocity" in g) and g.velocity.length() > 5.0) else 0.0


## Cowboy/garde dessiné en iso (duster, ceinturon, grand chapeau, bandana,
## visage selon l'orientation). Délègue au module partagé CharacterArt.
func _draw_person(world_pos: Vector2, facing: Vector2, pal: Dictionary, is_guard: bool,
		alert: bool, walk: float, recoil: float, flash: float) -> void:
	var base := Iso.project(world_pos)
	var f := Iso.project(world_pos + facing) - base
	if f.length() > 0.001:
		f = f.normalized()
	CharacterArt.draw_person(self, base, f, pal, is_guard, alert, walk, recoil, flash)


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
