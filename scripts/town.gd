extends Node2D
## town.gd
## Grand village western EXPLORABLE (vue iso). Caméra qui SUIT le cowboy : on
## déambule dans les rues, on croise des habitants, on inspecte les commerces
## (touche E = petit texte d'ambiance) et on entre dans la BANQUE (E) pour lancer
## le braquage. Collisions sur les bâtiments + le puits.

const SHEET := preload("res://assets/source_sheets/western_exterior_sheet.png")
const TEX := 1254.0

const R_SAND := Rect2(58, 58, 236, 214)
const R_BANK := Rect2(63, 1003, 251, 199)
const R_SALOON := Rect2(366, 1000, 240, 205)
const R_HOUSE := Rect2(648, 1010, 251, 192)
const R_SHED := Rect2(930, 1010, 240, 192)
const R_WAGON := Rect2(620, 600, 300, 200)
const R_CACTUS := Rect2(40, 555, 120, 200)
const R_BARREL := Rect2(40, 800, 120, 130)
const R_SIGN := Rect2(360, 800, 120, 160)

const SPEED := 250.0
const FLOOR := Rect2(0, 0, 2200, 1760)
const BANK_DOOR := Vector2(1100, 430)
const DOOR_RADIUS := 95.0
const PLAYER_RADIUS := 15.0
const TALK_RADIUS := 95.0
const WELL := Vector2(1100, 980)

var _player_pos := Vector2(1100, 1620)
var _facing := Vector2.UP
var _walk := 0.0
var _entered := false
var _hint_t := 0.0
var _can_enter := false
var _near_label := ""        # libellé du prompt d'action courant
var _target_kind := ""       # "bank" | "saloon" | "npc" | "flavor"
var _target_npc = null       # PNJ ciblé (Dictionary) si _target_kind == "npc"
var _target_flavor := ""
var _interact_was := false

var _buildings: Array[Dictionary] = []   # {region,pos,h,label,tint,flavor}
var _props: Array[Dictionary] = []        # {region,pos,h}
var _npcs: Array[Dictionary] = []         # {pos,facing,pal,phase}
var _foots: Array[Rect2] = []             # collisions

var _zoom := 2.0
var _cam := Vector2.ZERO
var _toast: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# Réapparition à la sortie du saloon (sinon, entrée du village).
	if GameManager.town_return_pos != Vector2.ZERO:
		_player_pos = GameManager.town_return_pos
		_facing = Vector2.DOWN
		GameManager.town_return_pos = Vector2.ZERO
	_build_town()
	_apply_zoom()
	_cam = _camera_target()
	position = _cam
	_build_ui()


# --- Construction du village ---

func _build_town() -> void:
	# Bâtiment cible, au fond de la grand-rue.
	_add_building(R_BANK, Vector2(1100, 230), 250.0, "★ BANQUE ★", Color(1, 1, 1),
			"", Vector2(210, 150))
	# Côté ouest de la rue (x ~ 760). Le SALOON est ENTRABLE.
	_add_building(R_SALOON, Vector2(760, 560), 210.0, "SALOON", Color(1.0, 0.92, 0.9),
			"Saloon Le Cactus — pousse les portes battantes.", Vector2(180, 120), "saloon")
	_add_building(R_HOUSE, Vector2(760, 900), 195.0, "HÔTEL", Color(0.92, 0.96, 1.0),
			"Hôtel de la Frontière — chambres à l'étage, 2 $ la nuit.", Vector2(180, 120))
	_add_building(R_SHED, Vector2(760, 1240), 185.0, "MAGASIN", Color(1.0, 0.96, 0.85),
			"Magasin général — cartouches, cordes, conserves de haricots.", Vector2(170, 115))
	_add_building(R_HOUSE, Vector2(760, 1560), 190.0, "ÉGLISE", Color(0.95, 0.95, 1.0),
			"Petite église en bois — une prière avant le casse ?", Vector2(170, 115))
	# Côté est de la rue (x ~ 1440).
	_add_building(R_HOUSE, Vector2(1440, 560), 195.0, "SHÉRIF", Color(0.85, 0.9, 1.0),
			"Bureau du shérif — mieux vaut filer avant qu'il ne rentre.", Vector2(180, 120))
	_add_building(R_SHED, Vector2(1440, 900), 185.0, "ÉCURIE", Color(0.95, 0.88, 0.78),
			"Écurie — ton cheval est sellé, prêt pour la fuite.", Vector2(170, 115))
	_add_building(R_SALOON, Vector2(1440, 1240), 205.0, "POSTE", Color(0.9, 1.0, 0.9),
			"Poste & télégraphe — « STOP braquage en cours STOP ».", Vector2(180, 120))
	_add_building(R_SHED, Vector2(1440, 1560), 185.0, "FORGE", Color(1.0, 0.9, 0.8),
			"Forge du maréchal-ferrant — l'odeur du fer chaud.", Vector2(170, 115))
	# Ruelle est (au-delà de la place).
	_add_building(R_HOUSE, Vector2(1820, 1020), 190.0, "DOCTEUR", Color(0.9, 1.0, 0.95),
			"Cabinet du Doc — whisky en guise d'anesthésie.", Vector2(170, 115))
	_add_building(R_SHED, Vector2(360, 1020), 185.0, "MAISON", Color(0.95, 0.92, 0.85),
			"Maison de ville — volets clos.", Vector2(170, 115))

	# Mobilier de rue (décor, sans collision).
	_add_prop(R_WAGON, Vector2(940, 760), 150.0)
	_add_prop(R_WAGON, Vector2(1280, 1360), 150.0)
	_add_prop(R_SIGN, Vector2(1100, 640), 100.0)
	_add_prop(R_BARREL, Vector2(960, 480), 78.0)
	_add_prop(R_BARREL, Vector2(1240, 520), 78.0)
	_add_prop(R_BARREL, Vector2(960, 1180), 78.0)
	_add_prop(R_BARREL, Vector2(1250, 1120), 78.0)
	for c in [Vector2(180, 560), Vector2(2020, 700), Vector2(160, 1480),
			Vector2(2040, 1500), Vector2(120, 900), Vector2(2080, 1100)]:
		_add_prop(R_CACTUS, c, 130.0)

	# Habitants : cowboys aux palettes variées, chacun a quelques répliques.
	_add_npc(Vector2(980, 1080), Vector2(1, 0.2), Color(0.30, 0.45, 0.55), Color(0.85, 0.8, 0.7),
			"Vieux Hank", ["La banque ? Personne n'a jamais réussi à la braquer...",
			"Le shérif a la gâchette facile, méfie-toi.",
			"De mon temps, l'or coulait à flots dans cette ville."])
	_add_npc(Vector2(1230, 880), Vector2(-1, 0.2), Color(0.45, 0.30, 0.45), Color(0.9, 0.85, 0.5),
			"Rosita", ["Tu as l'air d'un homme à histoires, étranger.",
			"Le coffre de la banque ? On dit qu'il faut un moment pour l'ouvrir."])
	_add_npc(Vector2(1100, 1180), Vector2(0, 1), Color(0.25, 0.35, 0.25), Color(0.8, 0.7, 0.55),
			"Petit Joe", ["Wow, t'as vu son flingue ?!", "Un jour je serai un hors-la-loi, moi aussi !"])
	_add_npc(Vector2(1180, 700), Vector2(-0.4, 1), Color(0.5, 0.4, 0.2), Color(0.95, 0.7, 0.2),
			"Marshal à la retraite", ["Range ce six-coups avant de t'attirer des ennuis.",
			"J'ai accroché mon étoile. La ville se débrouillera."])
	_add_npc(Vector2(1000, 1380), Vector2(1, -0.3), Color(0.5, 0.2, 0.2), Color(0.8, 0.75, 0.7),
			"Veuve Carson", ["Les temps sont durs depuis la fermeture de la mine.",
			"Garde tes distances, jeune homme."])
	_add_npc(Vector2(1300, 1480), Vector2(-1, -0.2), Color(0.2, 0.3, 0.5), Color(0.9, 0.9, 0.8),
			"Doc Whitman", ["Si tu te prends une balle, tu sais où me trouver.",
			"Le whisky soigne tout, ou presque."])
	_add_npc(Vector2(1700, 1080), Vector2(-1, 0.1), Color(0.4, 0.45, 0.3), Color(0.85, 0.6, 0.4),
			"Palefrenier", ["Ton cheval est sellé à l'écurie, prêt pour la fuite.",
			"File vite après le coup, ils lanceront une battue."])
	_add_npc(Vector2(520, 1080), Vector2(1, 0.1), Color(0.35, 0.3, 0.45), Color(0.9, 0.8, 0.6),
			"Prêcheur", ["Repens-toi, pécheur, avant qu'il ne soit trop tard !",
			"Que le Seigneur ait pitié de ton âme... et de ton butin."])

	# Puits central (collision).
	_foots.append(Rect2(WELL - Vector2(40, 36), Vector2(80, 72)))


func _add_building(region: Rect2, pos: Vector2, h: float, label: String, tint: Color,
		flavor: String, foot: Vector2, enter := "") -> void:
	_buildings.append({"region": region, "pos": pos, "h": h, "label": label,
			"tint": tint, "flavor": flavor, "enter": enter})
	_foots.append(Rect2(pos - Vector2(foot.x * 0.5, foot.y * 0.6), foot))


func _add_prop(region: Rect2, pos: Vector2, h: float) -> void:
	_props.append({"region": region, "pos": pos, "h": h})


func _add_npc(pos: Vector2, facing: Vector2, coat: Color, hat: Color,
		npc_name := "", lines: Array = []) -> void:
	var pal := CharacterArt.hero_palette()
	pal["coat"] = coat
	pal["coat_dark"] = coat.darkened(0.2)
	pal["shirt"] = coat.lightened(0.2)
	pal["hat"] = hat
	pal["hat_band"] = hat.darkened(0.3)
	pal["bandana"] = coat.lightened(0.3)
	_npcs.append({"pos": pos, "facing": facing.normalized(), "pal": pal, "phase": randf() * TAU,
			"name": npc_name, "lines": lines, "li": 0})


# --- Boucle ---

func _process(delta: float) -> void:
	if not _entered:
		var dir := Iso.screen_to_world(InputManager.get_move_vector())
		if dir.length() > 1.0:
			dir = dir.normalized()
		if dir.length() > 0.05:
			_facing = dir.normalized()
			_walk += delta * 10.0
		else:
			_walk = 0.0
		_move(dir * SPEED * delta)
		_update_interaction()
	for n in _npcs:
		NpcAI.update(n, delta, _blocked, _rng)
	_cam = _cam.lerp(_camera_target(), clampf(delta * 8.0, 0.0, 1.0))
	position = _cam
	_hint_t += delta
	queue_redraw()


## Choisit l'interaction la plus proche (banque, saloon, PNJ, commerce) et gère E.
func _update_interaction() -> void:
	_can_enter = _player_pos.distance_to(BANK_DOOR) < DOOR_RADIUS
	_near_label = ""
	_target_kind = ""
	_target_npc = null
	_target_flavor = ""
	if _can_enter:
		_target_kind = "bank"
		_near_label = "ENTRER dans la BANQUE"
	else:
		var best := TALK_RADIUS
		# Habitants à qui parler (priorité au plus proche).
		for n in _npcs:
			if (n["lines"] as Array).is_empty():
				continue
			var d := _player_pos.distance_to(n["pos"])
			if d < best:
				best = d
				_target_kind = "npc"
				_target_npc = n
				_near_label = "Parler à %s" % n["name"]
		# Commerces : entrer (saloon) ou observer (texte d'ambiance).
		for b in _buildings:
			if b["flavor"] == "" and b["enter"] == "":
				continue
			var d := _player_pos.distance_to(b["pos"] + Vector2(0, 60))
			if d < best:
				best = d
				if b["enter"] == "saloon":
					_target_kind = "saloon"
					_near_label = "Entrer au %s" % b["label"]
				else:
					_target_kind = "flavor"
					_target_flavor = b["flavor"]
					_near_label = b["label"]
	# Front montant de E.
	var held := InputManager.is_interact_held()
	if held and not _interact_was:
		match _target_kind:
			"bank": _enter_bank()
			"saloon": GameManager.goto_saloon()
			"npc": _talk(_target_npc)
			"flavor": _show_toast(_target_flavor)
	_interact_was = held


## Affiche la réplique courante d'un PNJ et passe à la suivante.
func _talk(npc) -> void:
	var lines: Array = npc["lines"]
	if lines.is_empty():
		return
	var i: int = npc["li"] % lines.size()
	npc["li"] = i + 1
	# Le PNJ s'arrête et se tourne vers le joueur (conversation).
	npc["state"] = "idle"
	npc["timer"] = 2.0
	npc["facing"] = (_player_pos - npc["pos"]).normalized()
	_facing = (npc["pos"] - _player_pos).normalized()
	_show_toast("%s : « %s »" % [npc["name"], lines[i]])


func _move(motion: Vector2) -> void:
	var p := _player_pos
	var nx := p + Vector2(motion.x, 0)
	if not _blocked(nx):
		p = nx
	var ny := p + Vector2(0, motion.y)
	if not _blocked(ny):
		p = ny
	p.x = clampf(p.x, FLOOR.position.x + 40, FLOOR.end.x - 40)
	p.y = clampf(p.y, FLOOR.position.y + 40, FLOOR.end.y - 40)
	_player_pos = p


func _blocked(pos: Vector2) -> bool:
	for r in _foots:
		if r.grow(PLAYER_RADIUS).has_point(pos):
			return true
	return false


func _enter_bank() -> void:
	_entered = true
	AudioManager.play("click")
	GameManager.start_mission()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameManager.goto_main_menu()


# --- Caméra qui suit le cowboy (bornée à la carte) ---

func _apply_zoom() -> void:
	var vp := get_viewport_rect().size
	_zoom = clampf(minf(vp.x, vp.y) / 380.0, 1.7, 2.8)
	scale = Vector2(_zoom, _zoom)


func _camera_target() -> Vector2:
	var vp := get_viewport_rect().size
	var b := _map_bounds()
	var focus := Iso.project(_player_pos) + Vector2(0, -16)
	var t := vp * 0.5 - focus * _zoom
	t.x = _clamp_axis(t.x, vp.x, b.position.x, b.end.x)
	t.y = _clamp_axis(t.y, vp.y, b.position.y, b.end.y)
	return t


func _clamp_axis(t: float, screen: float, bmin: float, bmax: float) -> float:
	var lo := screen - _zoom * bmax
	var hi := -_zoom * bmin
	if lo > hi:
		return screen * 0.5 - _zoom * (bmin + bmax) * 0.5
	return clampf(t, lo, hi)


func _map_bounds() -> Rect2:
	var c := [Iso.project(FLOOR.position), Iso.project(Vector2(FLOOR.end.x, FLOOR.position.y)),
			Iso.project(FLOOR.end), Iso.project(Vector2(FLOOR.position.x, FLOOR.end.y))]
	var mn: Vector2 = c[0]
	var mx: Vector2 = c[0]
	for p in c:
		mn = mn.min(p)
		mx = mx.max(p)
	mn.y -= 280.0
	return Rect2(mn, mx - mn)


func _on_viewport_resized() -> void:
	_apply_zoom()
	_cam = _camera_target()
	position = _cam


# --- Rendu iso (coords locales : la caméra = position/scale du noeud) ---

func _draw() -> void:
	_draw_ground()
	_draw_well()
	# Repère banque : halo doré + flèche flottante.
	var d := Iso.project(BANK_DOOR)
	for i in range(4):
		draw_circle(d + Vector2(0, -6), 70.0 - i * 14.0, Color(1.0, 0.85, 0.35, 0.10))
	var bob := sin(_hint_t * 3.0) * 4.0
	var arrow := d + Vector2(0, -60 + bob)
	draw_colored_polygon(PackedVector2Array([
		arrow + Vector2(-10, -10), arrow + Vector2(10, -10), arrow + Vector2(0, 2)]),
		Color(1.0, 0.85, 0.25))
	_text(arrow + Vector2(0, -16), "BANQUE", 15, Color(1.0, 0.92, 0.6))

	var items: Array[Dictionary] = []
	for b in _buildings:
		items.append({"d": Iso.depth(b["pos"]) - 40.0, "k": "b", "o": b})
	for p in _props:
		items.append({"d": Iso.depth(p["pos"]), "k": "p", "o": p})
	for n in _npcs:
		items.append({"d": Iso.depth(n["pos"]), "k": "n", "o": n})
	items.append({"d": Iso.depth(_player_pos), "k": "me", "o": null})
	items.sort_custom(func(a, b): return a["d"] < b["d"])
	for it in items:
		match it["k"]:
			"b": _draw_building(it["o"])
			"p": _billboard(it["o"]["region"], it["o"]["pos"], it["o"]["h"], Color.WHITE)
			"n":
				var n: Dictionary = it["o"]
				var f := _screen_facing(n["pos"], n["facing"])
				CharacterArt.draw_person(self, Iso.project(n["pos"]), f, n["pal"],
						false, false, float(n.get("walk", 0.0)), 0.0, 0.0)
			"me": _draw_me()

	# Bulles d'ambiance + marqueur "💬" pour les PNJ.
	for n in _npcs:
		var head := Iso.project(n["pos"]) + Vector2(0, -58)
		var bub := NpcAI.bubble(n)
		if bub != "":
			_text(head, bub, 15, Color(1, 1, 0.9))
		elif not (n["lines"] as Array).is_empty() and _player_pos.distance_to(n["pos"]) < TALK_RADIUS:
			_text(head, "💬", 16, Color(1, 1, 0.7))
	# Prompt d'action contextuel au-dessus du joueur.
	if _near_label != "" and int(_hint_t * 2.0) % 2 == 0:
		var pp := Iso.project(_player_pos) + Vector2(0, -66)
		_text(pp, "E : %s" % _near_label, 16, Color(1, 1, 0.7))


func _draw_ground() -> void:
	var cell := 160.0
	var y := FLOOR.position.y
	while y < FLOOR.end.y - 1.0:
		var x := FLOOR.position.x
		while x < FLOOR.end.x - 1.0:
			_sand_tile(x, y, minf(cell, FLOOR.end.x - x), minf(cell, FLOOR.end.y - y))
			x += cell
		y += cell
	# Grand-rue (terre plus sombre) + place centrale.
	draw_colored_polygon(_rect_diamond(Rect2(900, 120, 400, 1560)), Color(0.55, 0.42, 0.28, 0.45))
	draw_colored_polygon(_rect_diamond(Rect2(880, 860, 440, 320)), Color(0.5, 0.38, 0.25, 0.4))
	for b in _buildings:
		var pos: Vector2 = b["pos"]
		var plank := _rect_diamond(Rect2(pos.x - 95, pos.y + 30, 190, 70))
		draw_colored_polygon(plank, Color(0.52, 0.36, 0.20, 0.9))
		draw_polyline(_closed(plank), Color(0.35, 0.24, 0.13), 2.0)


## Puits de la place centrale (margelle + toit).
func _draw_well() -> void:
	var b := Iso.project(WELL)
	draw_colored_polygon(_diamond_shadow(b, 30.0), Color(0, 0, 0, 0.2))
	# Margelle en pierre.
	draw_colored_polygon(_rect_diamond(Rect2(WELL.x - 26, WELL.y - 22, 52, 44)), Color(0.5, 0.46, 0.42))
	draw_polyline(_closed(_rect_diamond(Rect2(WELL.x - 26, WELL.y - 22, 52, 44))), Color(0.3, 0.28, 0.25), 2.0)
	draw_circle(b + Vector2(0, -8), 12.0, Color(0.12, 0.12, 0.16))
	# Poteaux + toit.
	draw_line(b + Vector2(-18, -10), b + Vector2(-18, -54), Color(0.4, 0.27, 0.15), 4.0)
	draw_line(b + Vector2(18, -10), b + Vector2(18, -54), Color(0.4, 0.27, 0.15), 4.0)
	draw_colored_polygon(PackedVector2Array([
		b + Vector2(-26, -52), b + Vector2(0, -66), b + Vector2(26, -52), b + Vector2(0, -44)]),
		Color(0.55, 0.30, 0.18))


func _draw_building(b: Dictionary) -> void:
	_billboard(b["region"], b["pos"], b["h"], b["tint"])
	var top := Iso.project(b["pos"]) + Vector2(0, -b["h"] - 10)
	_sign(top, b["label"])


func _sign(center: Vector2, label: String) -> void:
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 14
	draw_rect(Rect2(center - Vector2(w * 0.5, 12), Vector2(w, 22)), Color(0.32, 0.20, 0.10))
	draw_rect(Rect2(center - Vector2(w * 0.5, 12), Vector2(w, 22)), Color(0.6, 0.45, 0.25), false, 2.0)
	draw_string(font, center - Vector2(w * 0.5 - 7, -3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(0.98, 0.92, 0.7))


func _sand_tile(x: float, y: float, w: float, h: float) -> void:
	var pts := PackedVector2Array([
		Iso.project(Vector2(x, y)), Iso.project(Vector2(x + w, y)),
		Iso.project(Vector2(x + w, y + h)), Iso.project(Vector2(x, y + h))])
	var p := R_SAND.position
	var s := R_SAND.size
	var uvs := PackedVector2Array([
		p / TEX, Vector2(p.x + s.x, p.y) / TEX,
		Vector2(p.x + s.x, p.y + s.y) / TEX, Vector2(p.x, p.y + s.y) / TEX])
	draw_colored_polygon(pts, Color.WHITE, uvs, SHEET)


func _billboard(region: Rect2, world_pos: Vector2, target_h: float, tint: Color) -> void:
	var base := Iso.project(world_pos)
	var aspect := region.size.x / region.size.y
	var h := target_h
	var w := h * aspect
	draw_colored_polygon(_diamond_shadow(base, w * 0.34), Color(0, 0, 0, 0.18))
	draw_texture_rect_region(SHEET, Rect2(base.x - w * 0.5, base.y - h, w, h), region, tint)


func _draw_me() -> void:
	var f := _screen_facing(_player_pos, _facing)
	CharacterArt.draw_person(self, Iso.project(_player_pos), f, CharacterArt.hero_palette(),
			false, false, _walk, 0.0, 0.0)


func _screen_facing(world_pos: Vector2, facing: Vector2) -> Vector2:
	var f := Iso.project(world_pos + facing) - Iso.project(world_pos)
	return f.normalized() if f.length() > 0.001 else Vector2.DOWN


# --- Primitives ---

func _rect_diamond(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		Iso.project(r.position), Iso.project(Vector2(r.end.x, r.position.y)),
		Iso.project(r.end), Iso.project(Vector2(r.position.x, r.end.y))])


func _diamond_shadow(center: Vector2, rx: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-rx, 0), center + Vector2(0, -rx * 0.5),
		center + Vector2(rx, 0), center + Vector2(0, rx * 0.5)])


func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var c := poly.duplicate()
	if c.size() > 0:
		c.append(c[0])
	return c


func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# --- UI (titre + bouton retour + contrôles tactiles + bandeau d'ambiance) ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	get_viewport().size_changed.connect(_on_viewport_resized)

	var title := Label.new()
	title.text = "EL DORADO — explore la ville (E pour observer / entrer)"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 4)
	title.position = Vector2(16, 12)
	layer.add_child(title)

	var back := Button.new()
	back.text = "← Menu"
	back.add_theme_font_size_override("font_size", 20)
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.position = Vector2(-150, 12)
	back.custom_minimum_size = Vector2(130, 44)
	back.pressed.connect(func() -> void: GameManager.goto_main_menu())
	layer.add_child(back)

	# Bandeau d'ambiance (texte affiché en bas quand on observe un lieu).
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Color(1, 1, 0.85))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_toast.add_theme_constant_override("outline_size", 5)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = 40
	_toast.offset_right = -40
	_toast.offset_top = -150
	_toast.offset_bottom = -64
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_toast)

	var mc := Control.new()
	mc.set_script(load("res://scripts/mobile_controls.gd"))
	mc.set("combat_buttons", false)
	mc.set("interact_only", true)
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(mc)


func _show_toast(text: String) -> void:
	if _toast == null:
		return
	AudioManager.play("click", -6.0)
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)
