extends Node2D
## town.gd
## Village western EXPLORABLE (vue iso, même projection que la mission).
## On déambule dans la grande rue, on croise des habitants, on lit les enseignes
## des commerces, et on entre dans la BANQUE (touche E / bouton E) pour lancer le
## braquage. Caméra qui suit le cowboy. Collisions sur les bâtiments.

const SHEET := preload("res://assets/source_sheets/western_exterior_sheet.png")
const TEX := 1254.0

# Régions de la planche extérieure (fonds transparents).
const R_SAND := Rect2(58, 58, 236, 214)
const R_BANK := Rect2(63, 1003, 251, 199)
const R_SALOON := Rect2(366, 1000, 240, 205)
const R_HOUSE := Rect2(648, 1010, 251, 192)
const R_SHED := Rect2(930, 1010, 240, 192)
const R_WAGON := Rect2(620, 600, 300, 200)
const R_CACTUS := Rect2(40, 555, 120, 200)
const R_BARREL := Rect2(40, 800, 120, 130)
const R_SIGN := Rect2(360, 800, 120, 160)

const SPEED := 240.0
const FLOOR := Rect2(0, 0, 1700, 1320)
const BANK_DOOR := Vector2(850, 400)
const DOOR_RADIUS := 95.0
const PLAYER_RADIUS := 15.0

var _player_pos := Vector2(850, 1180)
var _facing := Vector2.UP
var _walk := 0.0
var _entered := false
var _hint_t := 0.0
var _can_enter := false

var _buildings: Array[Dictionary] = []   # {region,pos,h,label,foot:Rect2,tint}
var _props: Array[Dictionary] = []        # {region,pos,h}
var _npcs: Array[Dictionary] = []         # {pos,facing,pal,phase}
var _foots: Array[Rect2] = []             # collisions (empreintes des bâtiments)

var _zoom := 1.0


func _ready() -> void:
	_build_town()
	_fit_camera()
	_build_ui()


# --- Construction du village ---

func _build_town() -> void:
	# Bâtiment cible : la BANQUE, au fond de la rue (imposante mais cadrée).
	_add_building(R_BANK, Vector2(850, 270), 240.0, "★ BANQUE ★", Color(1, 1, 1), Vector2(210, 150))
	# Commerces de gauche.
	_add_building(R_SALOON, Vector2(500, 520), 210.0, "SALOON", Color(1.0, 0.92, 0.9), Vector2(180, 120))
	_add_building(R_HOUSE, Vector2(500, 820), 195.0, "HÔTEL", Color(0.92, 0.96, 1.0), Vector2(180, 120))
	_add_building(R_SHED, Vector2(500, 1100), 185.0, "MAGASIN", Color(1.0, 0.96, 0.85), Vector2(170, 115))
	# Commerces de droite.
	_add_building(R_HOUSE, Vector2(1200, 520), 195.0, "SHÉRIF", Color(0.85, 0.9, 1.0), Vector2(180, 120))
	_add_building(R_SHED, Vector2(1200, 820), 185.0, "ÉCURIE", Color(0.95, 0.88, 0.78), Vector2(170, 115))
	_add_building(R_SALOON, Vector2(1200, 1100), 205.0, "POSTE", Color(0.9, 1.0, 0.9), Vector2(180, 120))

	# Mobilier de rue (sans collision bloquante, juste décor).
	_add_prop(R_WAGON, Vector2(660, 700), 150.0)
	_add_prop(R_SIGN, Vector2(1010, 560), 100.0)
	_add_prop(R_BARREL, Vector2(700, 480), 78.0)
	_add_prop(R_BARREL, Vector2(1000, 760), 78.0)
	_add_prop(R_BARREL, Vector2(720, 1000), 78.0)
	_add_prop(R_CACTUS, Vector2(180, 560), 130.0)
	_add_prop(R_CACTUS, Vector2(1520, 700), 130.0)
	_add_prop(R_CACTUS, Vector2(170, 1080), 120.0)
	_add_prop(R_CACTUS, Vector2(1540, 1120), 120.0)

	# Habitants : cowboys statiques (palettes variées) qui peuplent la rue.
	_add_npc(Vector2(720, 820), Vector2(1, 0.2), Color(0.30, 0.45, 0.55), Color(0.85, 0.8, 0.7))
	_add_npc(Vector2(1010, 640), Vector2(-1, 0.2), Color(0.45, 0.30, 0.45), Color(0.9, 0.85, 0.5))
	_add_npc(Vector2(880, 980), Vector2(0, 1), Color(0.25, 0.35, 0.25), Color(0.8, 0.7, 0.55))
	_add_npc(Vector2(960, 520), Vector2(-0.4, 1), Color(0.5, 0.4, 0.2), Color(0.95, 0.7, 0.2))


func _add_building(region: Rect2, pos: Vector2, h: float, label: String, tint: Color, foot: Vector2) -> void:
	_buildings.append({"region": region, "pos": pos, "h": h, "label": label, "tint": tint})
	# Empreinte de collision (le devant du bâtiment, un peu en retrait).
	_foots.append(Rect2(pos - Vector2(foot.x * 0.5, foot.y * 0.6), foot))


func _add_prop(region: Rect2, pos: Vector2, h: float) -> void:
	_props.append({"region": region, "pos": pos, "h": h})


func _add_npc(pos: Vector2, facing: Vector2, coat: Color, hat: Color) -> void:
	var pal := CharacterArt.hero_palette()
	pal["coat"] = coat
	pal["coat_dark"] = coat.darkened(0.2)
	pal["shirt"] = coat.lightened(0.2)
	pal["hat"] = hat
	pal["hat_band"] = hat.darkened(0.3)
	pal["bandana"] = coat.lightened(0.3)
	_npcs.append({"pos": pos, "facing": facing.normalized(), "pal": pal, "phase": randf() * TAU})


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
		_can_enter = _player_pos.distance_to(BANK_DOOR) < DOOR_RADIUS
		if _can_enter and InputManager.is_interact_held():
			_enter_bank()
	# Léger balancement des habitants.
	for n in _npcs:
		n["phase"] += delta * 2.0
	_hint_t += delta
	queue_redraw()


## Déplacement avec collision (séparation par axe contre les empreintes).
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


# --- Caméra fixe : montre TOUT le village (tableau qu'on parcourt à pied) ---

## Ajuste zoom + centrage pour que tout le village tienne à l'écran (la rue iso
## dérive en diagonale : une caméra-suiveuse perdrait la banque hors champ).
func _fit_camera() -> void:
	var vp := get_viewport_rect().size
	var b := _map_bounds()
	var s := minf((vp.x - 30.0) / b.size.x, (vp.y - 80.0) / b.size.y)
	_zoom = clampf(s, 0.3, 1.4)
	scale = Vector2(_zoom, _zoom)
	position = vp * 0.5 - b.get_center() * _zoom


func _map_bounds() -> Rect2:
	var c := [Iso.project(FLOOR.position), Iso.project(Vector2(FLOOR.end.x, FLOOR.position.y)),
			Iso.project(FLOOR.end), Iso.project(Vector2(FLOOR.position.x, FLOOR.end.y))]
	var mn: Vector2 = c[0]
	var mx: Vector2 = c[0]
	for p in c:
		mn = mn.min(p)
		mx = mx.max(p)
	mn.y -= 280.0   # marge pour la hauteur des bâtiments
	return Rect2(mn, mx - mn)


func _on_viewport_resized() -> void:
	_fit_camera()


# --- Rendu iso (coords locales : la caméra = position/scale du noeud) ---

func _draw() -> void:
	_draw_ground()
	# Halo doré + marqueur flottant devant la porte de la banque (repère de loin).
	var d := Iso.project(BANK_DOOR)
	for i in range(4):
		draw_circle(d + Vector2(0, -6), 70.0 - i * 14.0, Color(1.0, 0.85, 0.35, 0.10))
	var bob := sin(_hint_t * 3.0) * 4.0
	var arrow := d + Vector2(0, -60 + bob)
	draw_colored_polygon(PackedVector2Array([
		arrow + Vector2(-10, -10), arrow + Vector2(10, -10), arrow + Vector2(0, 2)]),
		Color(1.0, 0.85, 0.25))
	_text(arrow + Vector2(0, -16), "BANQUE", 15, Color(1.0, 0.92, 0.6))

	# Tout trié par profondeur (bâtiments, props, habitants, joueur).
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
						false, false, sin(n["phase"]) * 0.3 + 0.3, 0.0, 0.0)
			"me": _draw_me()

	# Invite d'entrée près de la banque.
	if _can_enter and int(_hint_t * 2.0) % 2 == 0:
		_text(d + Vector2(0, -110), "Appuie sur E pour ENTRER", 18, Color(1, 1, 0.6))


func _draw_ground() -> void:
	var cell := 150.0
	var y := FLOOR.position.y
	while y < FLOOR.end.y - 1.0:
		var x := FLOOR.position.x
		while x < FLOOR.end.x - 1.0:
			_sand_tile(x, y, minf(cell, FLOOR.end.x - x), minf(cell, FLOOR.end.y - y))
			x += cell
		y += cell
	# Rue principale : bande de terre plus sombre au centre.
	var road := _rect_diamond(Rect2(690, 120, 320, 1120))
	draw_colored_polygon(road, Color(0.55, 0.42, 0.28, 0.45))
	# Trottoirs en bois devant chaque bâtiment.
	for b in _buildings:
		var pos: Vector2 = b["pos"]
		var plank := _rect_diamond(Rect2(pos.x - 95, pos.y + 30, 190, 70))
		draw_colored_polygon(plank, Color(0.52, 0.36, 0.20, 0.9))
		draw_polyline(_closed(plank), Color(0.35, 0.24, 0.13), 2.0)


func _draw_building(b: Dictionary) -> void:
	_billboard(b["region"], b["pos"], b["h"], b["tint"])
	# Enseigne au-dessus.
	var top := Iso.project(b["pos"]) + Vector2(0, -b["h"] - 10)
	_sign(top, b["label"])


## Petite enseigne en bois avec texte.
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


# --- UI (titre + bouton retour + contrôles tactiles) ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	get_viewport().size_changed.connect(_on_viewport_resized)

	var title := Label.new()
	title.text = "EL DORADO — explore la ville, puis entre dans la BANQUE (E)"
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

	# Joystick + bouton E (entrer dans la banque) ; pas de tir en ville.
	var mc := Control.new()
	mc.set_script(load("res://scripts/mobile_controls.gd"))
	mc.set("combat_buttons", false)
	mc.set("interact_only", true)
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(mc)
