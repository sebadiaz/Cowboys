extends Node2D
## town.gd
## Extérieur western : on arrive en ville et on rejoint la banque à pied.
## Vue isométrique (même projection que la mission). Décor dessiné depuis
## western_exterior_sheet.png. Quand le cowboy atteint la porte de la BANQUE,
## la mission de braquage démarre. Échap / bouton = retour menu.

const SHEET := preload("res://assets/source_sheets/western_exterior_sheet.png")
const TEX := 1254.0

# Régions (planche extérieure, fonds déjà transparents).
const R_SAND := Rect2(58, 58, 236, 214)        # dalle de sable
const R_BANK := Rect2(63, 1003, 251, 199)       # façade claire ornée (banque)
const R_SALOON := Rect2(366, 1000, 240, 205)     # bâtiment rouge à étage
const R_HOUSE := Rect2(648, 1010, 251, 192)      # maison bois
const R_SHED := Rect2(930, 1010, 240, 192)       # cabane bois
const R_WAGON := Rect2(620, 600, 300, 200)       # chariot bâché
const R_CACTUS := Rect2(40, 555, 120, 200)       # cactus
const R_BARREL := Rect2(40, 800, 120, 130)       # baril
const R_SIGN := Rect2(360, 800, 120, 160)        # panneau

const SPEED := 230.0
const FLOOR := Rect2(0, 0, 1100, 760)
const BANK_DOOR := Vector2(560, 120)             # position monde de l'entrée
const DOOR_RADIUS := 70.0

var _player_pos := Vector2(560, 700)
var _facing := Vector2.UP
var _entered := false
var _props: Array[Dictionary] = []
var _offset := Vector2.ZERO
var _hint_t := 0.0


func _ready() -> void:
	var vp := get_viewport_rect().size
	_offset = vp * 0.5 - Iso.project(FLOOR.get_center()) + Vector2(0, 40)
	_build_props()
	_build_ui()


func _build_props() -> void:
	# Bâtiments du fond. La banque est au centre, derrière la porte.
	_add(R_BANK, Vector2(560, 60), 230.0, true)        # BANQUE (cible)
	_add(R_SALOON, Vector2(220, 70), 215.0)
	_add(R_SHED, Vector2(905, 80), 185.0)
	_add(R_HOUSE, Vector2(110, 150), 180.0)
	# Mobilier de rue.
	_add(R_WAGON, Vector2(820, 430), 150.0)
	_add(R_CACTUS, Vector2(150, 470), 120.0)
	_add(R_CACTUS, Vector2(980, 560), 120.0)
	_add(R_BARREL, Vector2(420, 300), 80.0)
	_add(R_BARREL, Vector2(700, 320), 80.0)
	_add(R_SIGN, Vector2(560, 360), 96.0)


func _add(region: Rect2, pos: Vector2, h: float, is_bank := false) -> void:
	_props.append({"region": region, "pos": pos, "h": h, "bank": is_bank})


func _process(delta: float) -> void:
	if not _entered:
		var dir := Iso.screen_to_world(InputManager.get_move_vector())
		if dir.length() > 1.0:
			dir = dir.normalized()
		if dir.length() > 0.05:
			_facing = dir.normalized()
		_player_pos += dir * SPEED * delta
		_player_pos.x = clampf(_player_pos.x, FLOOR.position.x + 30, FLOOR.end.x - 30)
		_player_pos.y = clampf(_player_pos.y, FLOOR.position.y + 30, FLOOR.end.y - 30)
		if _player_pos.distance_to(BANK_DOOR) < DOOR_RADIUS:
			_enter_bank()
	_hint_t += delta
	queue_redraw()


func _enter_bank() -> void:
	_entered = true
	GameManager.start_mission()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameManager.goto_main_menu()


# --- Rendu iso ---

func _draw() -> void:
	# Sol de sable (dalles).
	var cell := 132.0
	var y := FLOOR.position.y
	while y < FLOOR.end.y - 1.0:
		var x := FLOOR.position.x
		while x < FLOOR.end.x - 1.0:
			_sand_tile(x, y, min(cell, FLOOR.end.x - x), min(cell, FLOOR.end.y - y))
			x += cell
		y += cell

	# Halo de la porte de la banque.
	var d := Iso.project(BANK_DOOR) + _offset
	draw_circle(d, DOOR_RADIUS * 0.8, Color(0.95, 0.85, 0.3, 0.25))

	# Tout trié par profondeur (props + joueur).
	var items: Array[Dictionary] = []
	for p in _props:
		items.append({"d": Iso.depth(p["pos"]), "kind": "prop", "data": p})
	items.append({"d": Iso.depth(_player_pos), "kind": "player"})
	items.sort_custom(func(a, b): return a["d"] < b["d"])
	for it in items:
		if it["kind"] == "prop":
			_billboard(it["data"]["region"], it["data"]["pos"], it["data"]["h"])
			if it["data"]["bank"]:
				_text(Iso.project(it["data"]["pos"]) + _offset + Vector2(0, -it["data"]["h"] - 6),
						"BANQUE", 22, Color(0.95, 0.9, 0.5))
		else:
			_draw_player()

	# Indication clignotante.
	var label := "Va vers la BANQUE pour entrer"
	if int(_hint_t * 1.5) % 2 == 0:
		_text(d + Vector2(0, -90), "↑ ENTRER", 18, Color(1, 1, 0.6))


func _sand_tile(x: float, y: float, w: float, h: float) -> void:
	var pts := PackedVector2Array([
		Iso.project(Vector2(x, y)) + _offset,
		Iso.project(Vector2(x + w, y)) + _offset,
		Iso.project(Vector2(x + w, y + h)) + _offset,
		Iso.project(Vector2(x, y + h)) + _offset,
	])
	var p := R_SAND.position
	var s := R_SAND.size
	var uvs := PackedVector2Array([
		p / TEX, Vector2(p.x + s.x, p.y) / TEX,
		Vector2(p.x + s.x, p.y + s.y) / TEX, Vector2(p.x, p.y + s.y) / TEX,
	])
	draw_colored_polygon(pts, Color.WHITE, uvs, SHEET)


func _billboard(region: Rect2, world_pos: Vector2, target_h: float) -> void:
	var base := Iso.project(world_pos) + _offset
	var aspect := region.size.x / region.size.y
	var h := target_h
	var w := h * aspect
	# Ombre.
	draw_circle(base, w * 0.28, Color(0, 0, 0, 0.18))
	draw_texture_rect_region(SHEET, Rect2(base.x - w * 0.5, base.y - h, w, h), region)


func _draw_player() -> void:
	var base := Iso.project(_player_pos) + _offset
	var c := base + Vector2(0, -20.0)
	draw_circle(base, 16.0, Color(0, 0, 0, 0.22))
	draw_circle(c, 14.0, Color(0.45, 0.27, 0.13))           # corps
	draw_circle(c + Vector2(0, -8), 13.0, Color(0.30, 0.18, 0.08))  # chapeau
	var f := (Iso.project(_player_pos + _facing) - Iso.project(_player_pos))
	if f.length() > 0.001:
		f = f.normalized()
	draw_circle(c + f * 9.0, 3.0, Color(0.95, 0.85, 0.55))


func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# --- UI (titre + bouton retour + contrôles tactiles) ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := Label.new()
	title.text = "EL DORADO — dirige-toi vers la banque"
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

	# Joystick virtuel (déplacement seul, pas de boutons de combat en ville).
	var mc := Control.new()
	mc.set_script(load("res://scripts/mobile_controls.gd"))
	mc.set("combat_buttons", false)
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(mc)
