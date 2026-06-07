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
var biome: String = "desert"
var dynamite: Node = null
var hostages: Array = []
var _pal: Dictionary = {}

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
	if not has_node("WarmTint"):
		var warm := CanvasModulate.new()
		warm.name = "WarmTint"
		warm.color = Color(1.0, 0.97, 0.90)
		add_child(warm)
	_pal = _biome_palette()
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
	mn.y -= 60.0
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
	# Murs/cloisons (hauteur selon le drapeau "low" = comptoir).
	for w in walls:
		_box_walls.append({"rect": w["rect"], "outer": w["outer"], "low": w.get("low", false)})
	# Props pilotés par les données du niveau (rendus en dessin procédural).
	for p in props:
		if not (p is Array) or p.size() < 3:
			continue
		var t := str(p[0])
		var pos := Vector2(float(p[1]), float(p[2]))
		var h: float = float(p[3]) if p.size() > 3 else _default_h(t)
		_billboards.append({"type": t, "pos": pos, "h": h})
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
	if is_instance_valid(dynamite) and dynamite.visible:
		_shadow(dynamite.global_position, 10.0)
	for h in hostages:
		if is_instance_valid(h):
			_shadow(h.global_position, 12.0)
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
	if is_instance_valid(dynamite) and dynamite.visible:
		items.append({"d": Iso.depth(dynamite.global_position), "kind": "dyn"})
	for h in hostages:
		if is_instance_valid(h):
			items.append({"d": Iso.depth(h.global_position), "kind": "hostage", "node": h})

	items.sort_custom(func(a, b): return a["d"] < b["d"])
	for it in items:
		match it["kind"]:
			"wall": _draw_wall(it["data"])
			"bb":
				var d: Dictionary = it["data"]
				_draw_prop(d["type"], d["pos"], d["h"])
			"safe": _draw_safe()
			"loot": _draw_loot(it["node"])
			"guard": _draw_guard(it["node"])
			"dyn": _draw_dynamite(dynamite.global_position)
			"hostage": _draw_hostage(it["node"].global_position)
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
	var fr := floor_rect
	var cx := fr.get_center().x
	# Tapis rouge d'apparat : long chemin central qui mène à la salle des coffres.
	if is_instance_valid(safe):
		var ry0 := fr.position.y + 40.0
		var ry1 := fr.end.y - 30.0
		_runner(Vector2(cx, (ry0 + ry1) * 0.5), 150.0, ry1 - ry0,
				Color(0.58, 0.14, 0.13), Color(0.88, 0.70, 0.28))
		# Tapis prestige sous la porte du coffre.
		_rug(safe.global_position + Vector2(0, 96), 200, 150,
				Color(0.50, 0.12, 0.12), Color(0.90, 0.74, 0.30))
	else:
		_rug(fr.get_center(), 230, 200, Color(0.40, 0.20, 0.30), Color(0.80, 0.62, 0.30))
	# Lampes d'ambiance le long des murs (haut + côtés).
	var n := maxi(3, int(fr.size.x / 360.0))
	for i in range(n + 1):
		_lamp(Vector2(lerpf(fr.position.x + 60.0, fr.end.x - 60.0, float(i) / n), fr.position.y + 8.0))
	for j in range(3):
		var yy := lerpf(fr.position.y + 120.0, fr.end.y - 80.0, float(j) / 2.0)
		_lamp(Vector2(fr.position.x + 8.0, yy))
		_lamp(Vector2(fr.end.x - 8.0, yy))


## Long tapis rectangulaire (chemin de coffre) avec bordure et liseré central.
func _runner(center: Vector2, w: float, h: float, col: Color, accent: Color) -> void:
	var r := Rect2(center - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	var poly := _rect_diamond(r)
	draw_colored_polygon(poly, col)
	draw_polyline(_closed(poly), accent, 3.0)
	var inner := Rect2(center - Vector2(w * 0.5 - 12, h * 0.5 - 12), Vector2(w - 24, h - 24))
	draw_polyline(_closed(_rect_diamond(inner)), accent.darkened(0.15), 1.5)


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

# --- Sol : marbre clair (salle des coffres) + parquet chaud (hall) ---
func _draw_floor() -> void:
	var cell := 110.0
	var split := floor_rect.position.y + floor_rect.size.y * 0.46   # marbre derrière
	var y := floor_rect.position.y
	var row := 0
	while y < floor_rect.end.y - 1.0:
		var x := floor_rect.position.x
		var col := 0
		while x < floor_rect.end.x - 1.0:
			var w: float = min(cell, floor_rect.end.x - x)
			var h: float = min(cell, floor_rect.end.y - y)
			var marble := (y + h * 0.5) < split
			_floor_tile(x, y, w, h, (row + col) % 2 == 0, marble)
			x += cell
			col += 1
		y += cell
		row += 1
	draw_polyline(_closed(_rect_diamond(floor_rect)), Color(0.30, 0.20, 0.12), 3.0)


func _floor_tile(x: float, y: float, w: float, h: float, even: bool, marble: bool) -> void:
	var pts := PackedVector2Array([
		Iso.project(Vector2(x, y)), Iso.project(Vector2(x + w, y)),
		Iso.project(Vector2(x + w, y + h)), Iso.project(Vector2(x, y + h))])
	var base: Color
	if marble:
		base = _pal["marble_a"] if even else _pal["marble_b"]
		draw_colored_polygon(pts, base)
		draw_polyline(_closed(pts), Color(0.62, 0.60, 0.56), 1.0)
		# veinage discret.
		draw_line(Iso.project(Vector2(x + w * 0.2, y)), Iso.project(Vector2(x + w * 0.7, y + h)),
			base.darkened(0.07), 1.0)
	else:
		base = _pal["wood_a"] if even else _pal["wood_b"]
		draw_colored_polygon(pts, base)
		draw_line(Iso.project(Vector2(x, y + h * 0.5)), Iso.project(Vector2(x + w, y + h * 0.5)),
			base.darkened(0.13), 1.0)
		draw_polyline(_closed(pts), base.darkened(0.18), 1.0)
# --- Sortie : paillasson vert + chambranle en bois + panneau SORTIE ---
func _draw_exit() -> void:
	var pos: Vector2 = exit_zone.global_position
	var U := Vector2(0, -1)
	var r := Rect2(pos - Vector2(48, 48), Vector2(96, 96))
	var poly := _rect_diamond(r)
	draw_colored_polygon(poly, Color(0.22, 0.55, 0.26, 0.80))
	draw_polyline(_closed(poly), Color(0.40, 0.85, 0.42), 3.0)
	var inner := _rect_diamond(Rect2(pos - Vector2(30, 30), Vector2(60, 60)))
	draw_polyline(_closed(inner), Color(0.65, 0.95, 0.6, 0.7), 1.5)
	# Flèche pulsée vers le haut.
	var bob := sin(Time.get_ticks_msec() * 0.005) * 2.0
	var a := Iso.project(pos) + Vector2(0, -10 + bob)
	draw_colored_polygon(PackedVector2Array([
		a + Vector2(-9, 0), a + Vector2(9, 0), a + Vector2(0, -12)]), Color(0.5, 1.0, 0.5))
	_text_centered("SORTIE", Iso.project(pos) + Vector2(0, 6), 15, Color(0.92, 1.0, 0.9))
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

## Porte de coffre principale : GRANDE porte ronde en acier, volant à rayons,
## rivets, charnières, or — pièce maîtresse de la scène.
func _draw_safe() -> void:
	var base := Iso.project(safe.global_position)
	var U := Vector2(0, -1)
	var opened: bool = safe._is_open
	var steel := Color(0.45, 0.48, 0.53)
	var steel_d := Color(0.28, 0.31, 0.36)
	var gold := Color(0.92, 0.78, 0.34)
	# Encadrement (niche en pierre/béton).
	var fw := 60.0
	var fh := 116.0
	var fL := base + Vector2(-fw, 0)
	var fR := base + Vector2(fw, 0)
	draw_colored_polygon(PackedVector2Array([fL, fR, fR + U * fh, fL + U * fh]), Color(0.50, 0.43, 0.32))
	draw_colored_polygon(PackedVector2Array([
		fL + U * (fh - 12), fR + U * (fh - 12), fR + U * fh, fL + U * fh]), Color(0.40, 0.34, 0.25))
	# Renfoncement métallique sombre.
	var iw := 48.0
	var dL := base + Vector2(-iw, 0) + U * 8
	var dR := base + Vector2(iw, 0) + U * 8
	draw_colored_polygon(PackedVector2Array([dL, dR, dR + U * 96, dL + U * 96]), steel_d.darkened(0.35))
	var c := base + U * 56.0
	if opened:
		# Intérieur doré révélé + porte entrebâillée.
		for i in range(5):
			draw_circle(c, 44.0 - i * 8, Color(1.0, 0.85, 0.40, 0.09))
		for gx in [-22, -8, 6, 20]:
			for gy in [0, -10, -20]:
				draw_rect(Rect2(c + Vector2(gx - 5, gy - 3), Vector2(11, 6)), gold.darkened(0.05 + 0.02 * gy))
		c += Vector2(34, 0)   # porte poussée sur le côté
	# Disque de la porte.
	draw_circle(c + Vector2(2, 2), 40.0, Color(0, 0, 0, 0.25))
	draw_circle(c, 40.0, steel)
	draw_arc(c, 40.0, 0, TAU, 32, steel_d, 2.5)
	# Couronne de rivets.
	for k in range(20):
		var a := TAU * k / 20.0
		draw_circle(c + Vector2(cos(a), sin(a)) * 35.0, 1.8, steel_d)
	draw_circle(c, 30.0, steel.lightened(0.06))
	draw_arc(c, 26.0, 0, TAU, 28, gold, 2.0)
	draw_circle(c, 19.0, steel_d.lightened(0.05))
	# Volant à rayons.
	for k in range(6):
		var d := Vector2.RIGHT.rotated(TAU * k / 6.0)
		draw_line(c, c + d * 17.0, gold, 3.0)
		draw_circle(c + d * 17.0, 2.4, gold.darkened(0.1))
	draw_arc(c, 17.0, 0, TAU, 24, gold, 2.0)
	draw_circle(c, 6.5, gold)
	draw_circle(c, 3.0, steel_d)
	# Charnières (côté gauche du cadre).
	for hy in [0.3, 0.7]:
		draw_rect(Rect2(base + Vector2(-iw - 4, 0) + U * (96 * hy + 8), Vector2(8, 14)), steel_d)
	# Plaque-nom.
	var plate := base + U * (fh - 6)
	_text_centered("BANQUE", plate, 13, gold.lightened(0.15))
	# Progression / état (au-dessus).
	var head := Iso.project(safe.global_position) + Vector2(0, -fh - 6.0)
	if opened:
		_text_centered("OUVERT", head, 14, Color(0.95, 0.9, 0.4))
	else:
		var prog: float = safe._progress
		if safe._player_in_range or prog > 0.0:
			var w := 64.0
			draw_rect(Rect2(head + Vector2(-w * 0.5, -4), Vector2(w, 8)), Color(0, 0, 0, 0.65))
			draw_rect(Rect2(head + Vector2(-w * 0.5, -4), Vector2(w * prog, 8)), Color(0.95, 0.8, 0.2))
			if prog <= 0.01:
				_text_centered("Maintiens E", head + Vector2(0, -10), 13, Color(1, 1, 1))
## Butin : sac de toile rebondi avec $ + pièces d'or, légère lueur et flottement.
func _draw_loot(node: Node) -> void:
	var base := Iso.project(node.global_position)
	var U := Vector2(0, -1)
	var bob := sin(Time.get_ticks_msec() * 0.004 + base.x * 0.05) * 1.5
	var b := base + Vector2(0, bob)
	var gold := Color(0.92, 0.78, 0.34)
	for i in range(3):
		draw_circle(b + U * 10, 17.0 - i * 4, Color(1.0, 0.85, 0.35, 0.10))
	# Pièces au sol.
	for off in [Vector2(-9, 0), Vector2(9, -1), Vector2(0, 2)]:
		draw_colored_polygon(_ellipse(b + off, 4, 2.3), gold)
	# Corps du sac.
	var burlap := Color(0.80, 0.67, 0.42)
	draw_colored_polygon(_ellipse(b + U * 9, 12, 10), burlap)
	draw_colored_polygon(_ellipse(b + U * 7, 12, 10), burlap)
	draw_colored_polygon(_ellipse(b + U * 17, 8, 6), burlap.lightened(0.06))
	# Col noué.
	draw_line(b + U * 21, b + U * 25, Color(0.40, 0.28, 0.16), 2.5)
	draw_colored_polygon(_ellipse(b + U * 22, 5, 2.5), Color(0.55, 0.40, 0.22))
	# Symbole $.
	_text_centered("$", b + U * 11, 15, Color(0.45, 0.30, 0.12))
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



## Hauteur par défaut d'un prop selon son type.
func _default_h(t: String) -> float:
	match t:
		"counter": return 34.0
		"vault": return 96.0
		"desk": return 30.0
		"barrel": return 40.0
		"crate": return 38.0
		"shelf": return 78.0
		"plant": return 56.0
		"chair": return 36.0
		"money": return 18.0
		"poster": return 46.0
		"lamp": return 70.0
		"chandelier": return 0.0
		"painting": return 44.0
		"goldpile": return 16.0
		"clerk": return 56.0
		"dynamite": return 20.0
		_: return 40.0


# --- Aiguillage du rendu d'un prop ---
func _draw_prop(t: String, pos: Vector2, h: float) -> void:
	match t:
		"crate": _draw_crate(pos, h)
		"barrel": _draw_barrel(pos, h)
		"desk": _draw_desk(pos)
		"counter": _draw_counter_cage(pos)
		"vault": _draw_strongbox(pos)
		"shelf": _draw_shelf(pos)
		"plant": _draw_plant(pos)
		"chair": _draw_chair(pos)
		"money": _draw_money(pos)
		"poster": _draw_poster(pos)
		"lamp": _draw_floor_lamp(pos)
		"chandelier": _draw_chandelier(pos)
		"painting": _draw_painting(pos)
		"goldpile": _draw_goldpile(pos)
		"clerk": _draw_clerk(pos)
		"dynamite": _draw_dynamite(pos)
		_: _draw_crate(pos, h)


## Boîte iso générique : faces est/sud + dessus, contour léger.
func _iso_box(r: Rect2, h: float, top: Color, east: Color, south: Color) -> void:
	var b0 := Iso.project(r.position)
	var b1 := Iso.project(Vector2(r.end.x, r.position.y))
	var b2 := Iso.project(r.end)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var up := Vector2(0, -h)
	draw_colored_polygon(PackedVector2Array([b3, b2, b2 + up, b3 + up]), south)
	draw_colored_polygon(PackedVector2Array([b1, b2, b2 + up, b1 + up]), east)
	var topq := PackedVector2Array([b0 + up, b1 + up, b2 + up, b3 + up])
	draw_colored_polygon(topq, top)
	draw_polyline(_closed(topq), top.darkened(0.28), 1.0)


## Caisse en bois cartoon : planches + croix de renfort + ferrures.
func _draw_crate(pos: Vector2, h: float) -> void:
	var r := Rect2(pos - Vector2(17, 17), Vector2(34, 34))
	var wood := Color(0.74, 0.55, 0.32)
	_iso_box(r, h, wood.lightened(0.10), wood.darkened(0.20), wood)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var b2 := Iso.project(r.end)
	var up := Vector2(0, -h)
	# Croix sur la face sud.
	draw_line(b3, b2 + up, wood.darkened(0.30), 1.5)
	draw_line(b2, b3 + up, wood.darkened(0.30), 1.5)
	draw_line((b3 + b2) * 0.5, (b3 + b2) * 0.5 + up, wood.darkened(0.22), 1.0)
	# Ferrures aux coins.
	for cc in [b3, b2, b3 + up, b2 + up]:
		draw_circle(cc, 1.6, Color(0.30, 0.22, 0.14))


## Tonneau : douves galbées, cerclages, dessus elliptique.
func _draw_barrel(pos: Vector2, h: float) -> void:
	var base := Iso.project(pos)
	var w := 14.0
	var bulge := 3.0
	var top := base + Vector2(0, -h)
	var wood := Color(0.56, 0.37, 0.20)
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(-w, 0), base + Vector2(-w - bulge, -h * 0.5), base + Vector2(-w, -h),
		top, base]), wood.darkened(0.16))
	draw_colored_polygon(PackedVector2Array([
		base, top, base + Vector2(w, -h), base + Vector2(w + bulge, -h * 0.5), base + Vector2(w, 0)]), wood)
	for sx in [-0.5, 0.0, 0.5]:
		draw_line(base + Vector2(w * sx, -3), base + Vector2(w * sx, -h + 3), wood.darkened(0.28), 1.0)
	for cy in [-4.0, -h * 0.5, -h + 4.0]:
		var ww: float = (w + bulge) if cy == -h * 0.5 else w + 1.0
		draw_line(base + Vector2(-ww, cy), base + Vector2(ww, cy), Color(0.32, 0.24, 0.17), 2.0)
	var lid := PackedVector2Array()
	for i in range(13):
		var a := TAU * float(i) / 12.0
		lid.append(top + Vector2(cos(a) * w, sin(a) * w * 0.42))
	draw_colored_polygon(lid, wood.lightened(0.12))
	draw_polyline(lid, wood.darkened(0.3), 1.0)


## Bureau d'employé : plateau feutré, registre, lampe de banquier, tiroirs.
func _draw_desk(pos: Vector2) -> void:
	var r := Rect2(pos - Vector2(35, 21), Vector2(70, 42))
	var wood := Color(0.46, 0.31, 0.17)
	var hh := 30.0
	_iso_box(r, hh, wood.lightened(0.06), wood.darkened(0.2), wood)
	var b0 := Iso.project(r.position)
	var b1 := Iso.project(Vector2(r.end.x, r.position.y))
	var b2 := Iso.project(r.end)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var up := Vector2(0, -hh)
	# Plateau feutré vert.
	var topq := PackedVector2Array([b0 + up, b1 + up, b2 + up, b3 + up])
	var felt := PackedVector2Array()
	var ctr := (b0 + b1 + b2 + b3) * 0.25 + up
	for q in topq:
		felt.append(ctr.lerp(q, 0.72))
	draw_colored_polygon(felt, Color(0.20, 0.42, 0.28))
	# Registre + parchemin.
	draw_colored_polygon(_ellipse(ctr + Vector2(-6, -1), 6, 4), Color(0.85, 0.80, 0.66))
	draw_colored_polygon(_ellipse(ctr + Vector2(5, 1), 5, 3.5), Color(0.55, 0.18, 0.14))
	# Lampe de banquier (abat-jour vert + lueur).
	var lp := ctr + Vector2(9, -5)
	draw_circle(lp, 9.0, Color(1.0, 0.85, 0.45, 0.10))
	draw_line(lp, lp + Vector2(0, 6), Color(0.85, 0.7, 0.3), 1.5)
	draw_colored_polygon(_ellipse(lp + Vector2(0, -3), 5, 3), Color(0.16, 0.42, 0.24))
	draw_circle(lp + Vector2(0, -1), 1.6, Color(1.0, 0.92, 0.6))
	# Tiroirs (face sud) + poignées.
	draw_line((b3 + b2) * 0.5, (b3 + b2) * 0.5 + up, wood.darkened(0.3), 1.0)
	for v in [0.35, 0.7]:
		draw_circle((b3.lerp(b2, 0.25)) + up * (hh * v), 1.4, Color(0.9, 0.8, 0.4))
		draw_circle((b3.lerp(b2, 0.75)) + up * (hh * v), 1.4, Color(0.9, 0.8, 0.4))


## Cage de guichet (laiton) + plaque BANK, posée sur le comptoir.
func _draw_counter_cage(pos: Vector2) -> void:
	var base := Iso.project(pos)
	var U := Vector2(0, -1)
	var brass := Color(0.85, 0.68, 0.28)
	var top := 34.0       # hauteur du comptoir
	var cageh := 30.0
	var hw := 30.0
	var L := base + Vector2(-hw, 0) + U * top
	var R := base + Vector2(hw, 0) + U * top
	# Montants + traverse.
	draw_line(L, L + U * cageh, brass.darkened(0.2), 3.0)
	draw_line(R, R + U * cageh, brass.darkened(0.2), 3.0)
	draw_line(L + U * cageh, R + U * cageh, brass.darkened(0.2), 3.0)
	# Barreaux.
	for i in range(1, 7):
		var u := float(i) / 7.0
		draw_line(L.lerp(R, u), L.lerp(R, u) + U * cageh, brass, 1.5)
	# Guichet (ouverture basse).
	draw_colored_polygon(PackedVector2Array([
		L.lerp(R, 0.32), L.lerp(R, 0.68), L.lerp(R, 0.68) + U * 10, L.lerp(R, 0.32) + U * 10]),
		Color(0.10, 0.08, 0.06, 0.5))
	# Plaque BANK dorée.
	var plate := base + U * (top + cageh + 7)
	draw_rect(Rect2(plate + Vector2(-26, -8), Vector2(52, 16)), Color(0.30, 0.20, 0.10))
	draw_rect(Rect2(plate + Vector2(-26, -8), Vector2(52, 16)), brass, false, 1.5)
	_text_centered("BANK", plate + Vector2(0, 5), 13, brass.lightened(0.2))


## Coffre-fort secondaire (strongbox) : caisson métallique à petite porte ronde.
func _draw_strongbox(pos: Vector2) -> void:
	var r := Rect2(pos - Vector2(26, 18), Vector2(52, 36))
	var steel := Color(0.40, 0.43, 0.48)
	var hh := 56.0
	_iso_box(r, hh, steel.lightened(0.08), steel.darkened(0.22), steel)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var b2 := Iso.project(r.end)
	var up := Vector2(0, -hh)
	var c := (b3 + b2) * 0.5 + up * 0.55
	draw_circle(c, 11.0, steel.darkened(0.18))
	draw_circle(c, 8.0, steel.lightened(0.05))
	var gold := Color(0.90, 0.76, 0.32)
	for k in range(4):
		var d := Vector2.RIGHT.rotated(TAU * k / 4.0 + 0.4)
		draw_line(c, c + d * 7.0, gold, 1.5)
	draw_circle(c, 2.6, gold)
	# Rivets.
	for cc in [b3 + up, b2 + up]:
		draw_circle(cc + Vector2(0, 3), 1.4, steel.darkened(0.3))


## Étagère / registres : meuble haut avec rayonnages, livres et sacs d'or.
func _draw_shelf(pos: Vector2) -> void:
	var r := Rect2(pos - Vector2(34, 12), Vector2(68, 24))
	var wood := Color(0.42, 0.28, 0.16)
	var hh := 78.0
	_iso_box(r, hh, wood.lightened(0.05), wood.darkened(0.22), wood)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var b2 := Iso.project(r.end)
	var up := Vector2(0, -hh)
	# Rayonnages + livres colorés.
	var books := [Color(0.70, 0.25, 0.20), Color(0.25, 0.45, 0.55), Color(0.80, 0.62, 0.25),
		Color(0.35, 0.50, 0.32), Color(0.55, 0.30, 0.45)]
	for s in [0.32, 0.62, 0.9]:
		var sf := float(s)
		var sl: Vector2 = b3 + up * (hh * sf)
		var sr: Vector2 = b2 + up * (hh * sf)
		draw_line(sl, sr, wood.darkened(0.3), 2.0)
		for i in range(6):
			var u := (float(i) + 0.5) / 6.0
			var bp: Vector2 = sl.lerp(sr, u)
			draw_rect(Rect2(bp + Vector2(-2.5, -10), Vector2(5, 10)), books[(i + int(sf * 10)) % books.size()])
	# Sacs d'or sur l'étagère du bas.
	for u in [0.25, 0.75]:
		var gp := b3.lerp(b2, u) + up * (hh * 0.16)
		draw_colored_polygon(_ellipse(gp, 6, 4.5), Color(0.80, 0.66, 0.40))
		_text_centered("$", gp + Vector2(0, 3), 10, Color(0.5, 0.34, 0.14))


## Plante en pot (cactus/fougère décorative).
func _draw_plant(pos: Vector2) -> void:
	var base := Iso.project(pos)
	var U := Vector2(0, -1)
	# Pot.
	var pot := Color(0.66, 0.36, 0.22)
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(-9, 0), base + Vector2(9, 0), base + Vector2(7, -14), base + Vector2(-7, -14)]), pot)
	draw_colored_polygon(_ellipse(base + U * 14, 8, 3), pot.lightened(0.1))
	# Feuillage (plusieurs lobes verts).
	var green := Color(0.28, 0.5, 0.28)
	for ang in [-0.6, -0.2, 0.2, 0.6]:
		var tip := base + U * 14 + Vector2(sin(ang) * 16, -1) + U * (26.0 * cos(ang))
		draw_line(base + U * 14, tip, green.darkened(0.1), 3.0)
		draw_colored_polygon(_ellipse(tip, 4, 6), green)
	draw_colored_polygon(_ellipse(base + U * 30, 6, 7), green.lightened(0.05))


## Chaise en bois (dossier + assise).
func _draw_chair(pos: Vector2) -> void:
	var r := Rect2(pos - Vector2(11, 11), Vector2(22, 22))
	var wood := Color(0.50, 0.33, 0.18)
	_iso_box(r, 16.0, wood.lightened(0.05), wood.darkened(0.2), wood)
	var b0 := Iso.project(r.position)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var up := Vector2(0, -16)
	# Dossier (au fond).
	draw_colored_polygon(PackedVector2Array([
		b0 + up, b0 + up + Vector2(0, -16),
		(b3 + up).lerp(b0 + up, 0.0) + Vector2(0, 0)]), wood)
	draw_line(b0 + up, b0 + up + Vector2(0, -16), wood.darkened(0.2), 3.0)


## Pile de billets / sacs d'or (butin décoratif derrière le comptoir).
func _draw_money(pos: Vector2) -> void:
	var base := Iso.project(pos)
	var gold := Color(0.92, 0.78, 0.34)
	# Lueur dorée.
	for i in range(3):
		draw_circle(base + Vector2(0, -6), 14.0 - i * 4, Color(1.0, 0.85, 0.35, 0.08))
	# Liasses empilées.
	for i in range(3):
		var y := -i * 5.0
		draw_colored_polygon(_ellipse(base + Vector2(-5, y), 7, 3.5), Color(0.55, 0.72, 0.45))
		draw_line(base + Vector2(-12, y), base + Vector2(2, y), Color(0.35, 0.5, 0.3), 1.0)
	# Pièces d'or.
	for off in [Vector2(7, -1), Vector2(11, -3), Vector2(8, -5)]:
		draw_colored_polygon(_ellipse(base + off, 4, 2.4), gold)
		draw_polyline(_closed(_ellipse(base + off, 4, 2.4)), gold.darkened(0.25), 1.0)


## Affiche WANTED debout (panneau cloué).
func _draw_poster(pos: Vector2) -> void:
	var base := Iso.project(pos)
	var U := Vector2(0, -1)
	var paper := Color(0.86, 0.78, 0.58)
	var w := 22.0
	var top := 46.0
	var bot := 16.0
	var L := base + Vector2(-w * 0.5, 0)
	var Rr := base + Vector2(w * 0.5, 0)
	draw_colored_polygon(PackedVector2Array([
		L + U * bot, Rr + U * bot, Rr + U * top, L + U * top]), paper)
	draw_polyline(_closed(PackedVector2Array([
		L + U * bot, Rr + U * bot, Rr + U * top, L + U * top])), Color(0.45, 0.32, 0.18), 1.5)
	_text_centered("WANTED", base + U * (top - 6), 9, Color(0.35, 0.20, 0.12))
	draw_colored_polygon(_ellipse(base + U * ((top + bot) * 0.5), 6, 7), Color(0.55, 0.40, 0.26))
	_text_centered("$$$", base + U * (bot + 6), 9, Color(0.4, 0.25, 0.12))


## Lampadaire / lampe à pétrole sur pied (lueur chaude).
func _draw_floor_lamp(pos: Vector2) -> void:
	var base := Iso.project(pos)
	var U := Vector2(0, -1)
	draw_line(base, base + U * 56, Color(0.25, 0.18, 0.10), 3.0)
	var head := base + U * 58
	for i in range(4):
		draw_circle(head, 22.0 - i * 5, Color(1.0, 0.84, 0.42, 0.07))
	draw_colored_polygon(_ellipse(head, 6, 7), Color(0.85, 0.7, 0.35))
	draw_circle(head, 3.0, Color(1.0, 0.92, 0.6))


## Mur : intérieur en plâtre + plinthe/corniche bois, ou extérieur en brique.
## Les murs "low" (drapeau) deviennent un vrai comptoir bois avec plateau verni.
func _draw_wall(wd: Dictionary) -> void:
	var r: Rect2 = wd["rect"]
	if wd.get("low", false):
		_draw_counter_base(r)
		return
	var outer: bool = wd.get("outer", false)
	var h := 50.0                                   # murs hauts = vraie pièce fermée
	var b0 := Iso.project(r.position)
	var b1 := Iso.project(Vector2(r.end.x, r.position.y))
	var b2 := Iso.project(r.end)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var up := Vector2(0, -h)
	# Palette CONTRASTÉE : plâtre crème clair (intérieur) / adobe chaud (extérieur),
	# bien plus clairs que le sol pour que la salle se "lise".
	var face: Color = _pal["outer"] if outer else _pal["wall"]
	var faceE := face.darkened(0.14)
	draw_colored_polygon(PackedVector2Array([b3, b2, b2 + up, b3 + up]), face)
	draw_colored_polygon(PackedVector2Array([b1, b2, b2 + up, b1 + up]), faceE)
	if outer:
		# Assises de brique adobe.
		for k in range(1, 5):
			var vy := -h * float(k) / 5.0
			draw_line(b3 + Vector2(0, vy), b2 + Vector2(0, vy), face.darkened(0.16), 1.0)
			draw_line(b1 + Vector2(0, vy), b2 + Vector2(0, vy), face.darkened(0.16), 1.0)
	else:
		# Lambris bois en bas (plinthe haute ~18 px) + cimaise.
		var wood: Color = _pal["trim"]
		var wsh := 18.0
		draw_colored_polygon(PackedVector2Array([b3, b2, b2 + Vector2(0, -wsh), b3 + Vector2(0, -wsh)]), wood)
		draw_colored_polygon(PackedVector2Array([b1, b2, b2 + Vector2(0, -wsh), b1 + Vector2(0, -wsh)]), wood.darkened(0.12))
		draw_line(b3 + Vector2(0, -wsh), b2 + Vector2(0, -wsh), wood.lightened(0.15), 1.5)
		draw_line(b1 + Vector2(0, -wsh), b2 + Vector2(0, -wsh), wood.lightened(0.15), 1.5)
		# Cimaise sous la corniche.
		draw_line(b3 + up + Vector2(0, 8), b2 + up + Vector2(0, 8), wood, 2.0)
		draw_line(b1 + up + Vector2(0, 8), b2 + up + Vector2(0, 8), wood.darkened(0.12), 2.0)
	# Corniche (dessus) + arête sombre pour détacher du fond.
	var topq := PackedVector2Array([b0 + up, b1 + up, b2 + up, b3 + up])
	draw_colored_polygon(topq, face.darkened(0.10) if outer else face.lightened(0.12))
	draw_polyline(_closed(topq), face.darkened(0.32), 1.5)


## Comptoir de guichets (base des murs "low") : meuble bois à plateau verni.
func _draw_counter_base(r: Rect2) -> void:
	var hh := 32.0
	var wood := Color(0.52, 0.34, 0.18)
	var b0 := Iso.project(r.position)
	var b1 := Iso.project(Vector2(r.end.x, r.position.y))
	var b2 := Iso.project(r.end)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var up := Vector2(0, -hh)
	# Corps.
	draw_colored_polygon(PackedVector2Array([b3, b2, b2 + up, b3 + up]), wood)
	draw_colored_polygon(PackedVector2Array([b1, b2, b2 + up, b1 + up]), wood.darkened(0.16))
	# Panneaux moulurés (face sud).
	var segs := maxi(2, int(b3.distance_to(b2) / 26.0))
	for i in range(segs):
		var u0 := (float(i) + 0.16) / segs
		var u1 := (float(i) + 0.84) / segs
		draw_polyline(_closed(PackedVector2Array([
			b3.lerp(b2, u0) + up * 0.3, b3.lerp(b2, u1) + up * 0.3,
			b3.lerp(b2, u1) + up * 0.85, b3.lerp(b2, u0) + up * 0.85])), wood.darkened(0.28), 1.0)
	# Plateau verni qui déborde un peu (overhang).
	var ov := Vector2(0, 4)
	var topq := PackedVector2Array([b0 + up, b1 + up, b2 + up + ov, b3 + up + ov])
	draw_colored_polygon(topq, Color(0.62, 0.42, 0.22))
	draw_polyline(_closed(topq), Color(0.78, 0.60, 0.34), 1.5)



## Lustre suspendu : chaîne + couronne de bougies + lueur chaude.
func _draw_chandelier(pos: Vector2) -> void:
	var p := Iso.project(pos)
	var ring := p + Vector2(0, -96)
	draw_line(p + Vector2(0, -150), ring, Color(0.25, 0.18, 0.10), 2.0)
	for i in range(5):
		draw_circle(ring, 34.0 - i * 6.0, Color(1.0, 0.84, 0.42, 0.06))
	# Anneau métallique + bras.
	draw_arc(ring, 16.0, 0, TAU, 22, Color(0.55, 0.42, 0.20), 2.5)
	for k in range(6):
		var a := TAU * k / 6.0
		var bp := ring + Vector2(cos(a), sin(a) * 0.55) * 16.0
		draw_line(ring, bp, Color(0.55, 0.42, 0.20), 2.0)
		draw_line(bp, bp + Vector2(0, -6), Color(0.95, 0.9, 0.75), 2.0)      # bougie
		draw_circle(bp + Vector2(0, -8), 2.2, Color(1.0, 0.92, 0.6))         # flamme
	draw_circle(ring, 3.0, Color(0.6, 0.45, 0.22))


## Tableau encadré (cadre doré + petite scène western : soleil + mesa).
func _draw_painting(pos: Vector2) -> void:
	var base := Iso.project(pos)
	var U := Vector2(0, -1)
	var w := 30.0
	var bot := 16.0
	var top := 44.0
	var L := base + Vector2(-w * 0.5, 0)
	var R := base + Vector2(w * 0.5, 0)
	var mid := (bot + top) * 0.5
	# Cadre doré + toile + ciel.
	draw_colored_polygon(PackedVector2Array([
		L + U * (bot - 3), R + U * (bot - 3), R + U * (top + 3), L + U * (top + 3)]),
		Color(0.78, 0.60, 0.24))
	draw_colored_polygon(PackedVector2Array([
		L + U * bot, R + U * bot, R + U * top, L + U * top]), Color(0.55, 0.40, 0.26))
	draw_colored_polygon(PackedVector2Array([
		L + U * mid, R + U * mid, R + U * top, L + U * top]), Color(0.95, 0.78, 0.50))
	draw_circle(base + U * (top - 8), 4.0, Color(1.0, 0.86, 0.45))
	draw_colored_polygon(PackedVector2Array([
		L.lerp(R, 0.2) + U * bot, L.lerp(R, 0.45) + U * mid, L.lerp(R, 0.7) + U * bot]),
		Color(0.50, 0.34, 0.24))


## Tas d'or : lingots empilés + pièces, lueur dorée (près du coffre).
func _draw_goldpile(pos: Vector2) -> void:
	var b := Iso.project(pos)
	var gold := Color(0.93, 0.79, 0.34)
	for i in range(3):
		draw_circle(b + Vector2(0, -6), 18.0 - i * 5, Color(1.0, 0.85, 0.35, 0.10))
	# Lingots (rangée + dessus).
	for x in [-10.0, 0.0, 10.0]:
		draw_colored_polygon(PackedVector2Array([
			b + Vector2(x - 6, 0), b + Vector2(x + 6, 0), b + Vector2(x + 5, -6), b + Vector2(x - 5, -6)]), gold)
		draw_polyline(_closed(PackedVector2Array([
			b + Vector2(x - 6, 0), b + Vector2(x + 6, 0), b + Vector2(x + 5, -6), b + Vector2(x - 5, -6)])),
			gold.darkened(0.25), 1.0)
	draw_colored_polygon(PackedVector2Array([
		b + Vector2(-6, -6), b + Vector2(6, -6), b + Vector2(5, -12), b + Vector2(-5, -12)]), gold.lightened(0.08))
	for off in [Vector2(-12, 1), Vector2(12, 0)]:
		draw_colored_polygon(_ellipse(b + off, 4, 2.4), gold)


## Guichetier : citoyen statique derrière le comptoir (vie de la banque).
func _draw_clerk(pos: Vector2) -> void:
	var pal := {
		"hat": Color(0.20, 0.16, 0.12), "hat_band": Color(0.12, 0.09, 0.06),
		"coat": Color(0.30, 0.24, 0.20), "coat_dark": Color(0.22, 0.17, 0.14),
		"shirt": Color(0.88, 0.84, 0.74), "pants": Color(0.26, 0.22, 0.18),
		"skin": Color(0.88, 0.68, 0.50), "bandana": Color(0.55, 0.18, 0.16),
		"belt": Color(0.18, 0.13, 0.09), "buckle": Color(0.85, 0.72, 0.32),
		"boots": Color(0.20, 0.14, 0.09), "hair": Color(0.18, 0.13, 0.09),
	}
	var base := Iso.project(pos)
	CharacterArt.draw_person(self, base, Vector2(0, 1), pal, false, false, 0.0, 0.0, 0.0)


## Otage : civil retenu (mains liées) + marqueur d'alerte pulsé "AIDE".
func _draw_hostage(pos: Vector2) -> void:
	var base := Iso.project(pos)
	# Halo pulsé pour attirer l'oeil.
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	draw_circle(base, 16.0 + pulse * 4.0, Color(0.95, 0.85, 0.35, 0.10))
	var pal := {
		"hat": Color(0.55, 0.42, 0.26), "hat_band": Color(0.40, 0.30, 0.18),
		"coat": Color(0.40, 0.50, 0.40), "coat_dark": Color(0.30, 0.40, 0.30),
		"shirt": Color(0.90, 0.88, 0.80), "pants": Color(0.34, 0.30, 0.26),
		"skin": Color(0.90, 0.72, 0.54), "bandana": Color(0.70, 0.66, 0.58),
		"belt": Color(0.30, 0.22, 0.14), "buckle": Color(0.70, 0.60, 0.30),
		"boots": Color(0.26, 0.18, 0.12), "hair": Color(0.30, 0.22, 0.14),
	}
	CharacterArt.draw_person(self, base, Vector2(0, 1), pal, false, false, 0.0, 0.0, 0.0)
	# Corde aux poignets.
	draw_line(base + Vector2(-5, -14), base + Vector2(5, -14), Color(0.55, 0.40, 0.22), 2.0)
	# Bulle "AIDE !".
	var head := base + Vector2(0, -52)
	draw_rect(Rect2(head + Vector2(-18, -10), Vector2(36, 16)), Color(0.1, 0.08, 0.05, 0.8))
	_text_centered("AIDE !", head + Vector2(0, 3), 12, Color(1.0, 0.85, 0.4))


## Caisse de dynamite (objet ramassable) : bâtons rouges + mèche + lueur.
func _draw_dynamite(pos: Vector2) -> void:
	var b := Iso.project(pos)
	var U := Vector2(0, -1)
	var bob := sin(Time.get_ticks_msec() * 0.005 + b.x * 0.05) * 1.5
	b += Vector2(0, bob)
	for i in range(3):
		draw_circle(b + U * 8, 14.0 - i * 4, Color(1.0, 0.55, 0.20, 0.10))
	# Trois bâtons.
	for dx in [-5.0, 0.0, 5.0]:
		draw_colored_polygon(PackedVector2Array([
			b + Vector2(dx - 3, 0), b + Vector2(dx + 3, 0),
			b + Vector2(dx + 3, -16), b + Vector2(dx - 3, -16)]), Color(0.74, 0.18, 0.14))
		draw_line(b + Vector2(dx, -3), b + Vector2(dx, -13), Color(0.95, 0.85, 0.7), 1.0)
	# Cerclage + mèche + étincelle.
	draw_line(b + Vector2(-8, -8), b + Vector2(8, -8), Color(0.30, 0.22, 0.14), 2.0)
	draw_line(b + Vector2(0, -16), b + Vector2(5, -22), Color(0.2, 0.16, 0.1), 1.5)
	draw_circle(b + Vector2(5, -22), 2.2, Color(1.0, 0.9, 0.4))


## Palette d'intérieur selon le biome de la ville (sol + murs).
func _biome_palette() -> Dictionary:
	match biome:
		"canyon":
			return {"wood_a": Color(0.62, 0.40, 0.26), "wood_b": Color(0.54, 0.34, 0.22),
				"marble_a": Color(0.82, 0.60, 0.46), "marble_b": Color(0.72, 0.50, 0.38),
				"wall": Color(0.85, 0.62, 0.46), "outer": Color(0.66, 0.40, 0.30),
				"trim": Color(0.45, 0.26, 0.16)}
		"plains":
			return {"wood_a": Color(0.60, 0.46, 0.28), "wood_b": Color(0.53, 0.40, 0.24),
				"marble_a": Color(0.85, 0.85, 0.74), "marble_b": Color(0.73, 0.76, 0.62),
				"wall": Color(0.86, 0.86, 0.70), "outer": Color(0.66, 0.66, 0.46),
				"trim": Color(0.42, 0.35, 0.18)}
		"snow":
			return {"wood_a": Color(0.58, 0.52, 0.48), "wood_b": Color(0.51, 0.46, 0.43),
				"marble_a": Color(0.91, 0.94, 0.98), "marble_b": Color(0.79, 0.84, 0.91),
				"wall": Color(0.90, 0.94, 0.99), "outer": Color(0.70, 0.78, 0.86),
				"trim": Color(0.46, 0.46, 0.54)}
		"night":
			return {"wood_a": Color(0.36, 0.32, 0.32), "wood_b": Color(0.31, 0.28, 0.28),
				"marble_a": Color(0.44, 0.46, 0.56), "marble_b": Color(0.36, 0.38, 0.48),
				"wall": Color(0.48, 0.50, 0.62), "outer": Color(0.33, 0.35, 0.45),
				"trim": Color(0.27, 0.27, 0.33)}
		_:
			return {"wood_a": Color(0.64, 0.47, 0.29), "wood_b": Color(0.57, 0.41, 0.25),
				"marble_a": Color(0.88, 0.84, 0.76), "marble_b": Color(0.76, 0.72, 0.66),
				"wall": Color(0.91, 0.85, 0.72), "outer": Color(0.80, 0.64, 0.45),
				"trim": Color(0.46, 0.31, 0.18)}


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
