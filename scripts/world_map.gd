extends Control
## world_map.gd
## Carte du monde "parchemin" du Far West : plusieurs villes reliées par une piste
## en pointillés. Chaque ville mène à sa banque (mission). Les villes se débloquent
## au fil des réussites. UI construite en code (desktop + mobile tactile).

const MARGIN := Vector2(0.10, 0.16)     # marges normalisées autour de la zone carte
const PIN := Vector2(196.0, 66.0)

var _pins: Array[Dictionary] = []        # { "idx": int, "btn": Button }
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Titre.
	var title := _label("CARTE DU TERRITOIRE", 34, Color(0.36, 0.20, 0.10))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position = Vector2(0, 14)
	add_child(title)
	var sub := _label("Choisis ta ville — chaque banque est un braquage", 18, Color(0.42, 0.28, 0.16))
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.position = Vector2(0, 56)
	add_child(sub)
	# Magot.
	var magot := _label("Magot : %d $" % SaveManager.total_money, 18, Color(0.30, 0.20, 0.12))
	magot.set_anchors_preset(Control.PRESET_TOP_WIDE)
	magot.position = Vector2(0, 84)
	add_child(magot)
	# Pastilles de ville.
	for i in range(1, GameManager.TOWNS.size() + 1):
		var b := _make_pin(i)
		add_child(b)
		_pins.append({"idx": i, "btn": b})
	# Boutons bas.
	var back := Button.new()
	back.text = "← Menu"
	back.add_theme_font_size_override("font_size", 20)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.position = Vector2(20, -64)
	back.custom_minimum_size = Vector2(150, 48)
	back.pressed.connect(func() -> void: GameManager.goto_main_menu())
	add_child(back)

	var quick := Button.new()
	quick.text = "⚡ Niveau rapide"
	quick.add_theme_font_size_override("font_size", 18)
	quick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quick.position = Vector2(-220, -64)
	quick.custom_minimum_size = Vector2(200, 48)
	quick.pressed.connect(func() -> void: GameManager.goto_level_select())
	add_child(quick)

	resized.connect(_layout)
	_layout()
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# Pulse de la ville courante (repère "tu es ici").
	for pd in _pins:
		var b: Button = pd["btn"]
		if pd["idx"] == GameManager.current_town and GameManager.town_unlocked(pd["idx"]):
			b.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.95, 0.6), 0.5 + 0.5 * sin(_t * 4.0))
		else:
			b.modulate = Color.WHITE
	queue_redraw()


# --- Placement (recalculé à chaque redimensionnement) ---

func _inner() -> Rect2:
	var m := Vector2(size.x * MARGIN.x, size.y * MARGIN.y)
	return Rect2(m, size - m * 2.0)


func _map_point(p: Array) -> Vector2:
	var r := _inner()
	return r.position + Vector2(float(p[0]) * r.size.x, float(p[1]) * r.size.y)


func _layout() -> void:
	for pd in _pins:
		var t := GameManager.town_def(pd["idx"])
		var c := _map_point(t["pos"])
		(pd["btn"] as Button).position = c - PIN * 0.5
	queue_redraw()


# --- Rendu de la carte (parchemin + reliefs + piste) ---

func _draw() -> void:
	# Fond parchemin.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.86, 0.76, 0.55))
	# Taches d'usure.
	for s in [[0.2, 0.3, 70.0], [0.7, 0.25, 90.0], [0.5, 0.8, 110.0], [0.85, 0.7, 60.0]]:
		draw_circle(Vector2(float(s[0]) * size.x, float(s[1]) * size.y), float(s[2]),
				Color(0.62, 0.50, 0.32, 0.10))
	# Cadre "brûlé".
	for i in range(3):
		var inset := 6.0 + i * 5.0
		draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0),
				Color(0.40, 0.27, 0.14, 0.5 - i * 0.12), false, 3.0)

	var inner := _inner()
	# Reliefs : chaîne de montagnes en haut.
	var ridge := inner.position.y + 6.0
	for k in range(7):
		var bx := lerpf(inner.position.x, inner.end.x, float(k) / 6.0)
		var pk := Vector2(bx, ridge + (10.0 if k % 2 == 0 else 26.0))
		var bw := inner.size.x / 9.0
		draw_colored_polygon(PackedVector2Array([
			pk + Vector2(-bw, 50), pk, pk + Vector2(bw, 50)]), Color(0.66, 0.56, 0.40))
		draw_colored_polygon(PackedVector2Array([
			pk + Vector2(-9, 14), pk, pk + Vector2(9, 14)]), Color(0.93, 0.92, 0.88))
	# Rivière sinueuse (bleu pâle).
	var river := PackedVector2Array()
	for k in range(17):
		var u := float(k) / 16.0
		river.append(Vector2(lerpf(inner.position.x + 30, inner.end.x - 30, u),
				inner.end.y - 40 + sin(u * 7.0) * 26.0))
	draw_polyline(river, Color(0.50, 0.62, 0.70, 0.7), 5.0)
	# Cactus décoratifs.
	for cp in [[0.06, 0.5], [0.95, 0.45], [0.5, 0.95]]:
		_cactus(_map_point(cp))

	# Piste en pointillés reliant les villes dans l'ordre.
	for i in range(1, GameManager.TOWNS.size()):
		var a := _map_point(GameManager.town_def(i)["pos"])
		var b := _map_point(GameManager.town_def(i + 1)["pos"])
		_dashed(a, b, Color(0.42, 0.28, 0.15, 0.9), 3.0, 12.0)

	# Rose des vents (bas-droite).
	_compass(Vector2(inner.end.x - 46, inner.position.y + 60))


func _cactus(p: Vector2) -> void:
	var g := Color(0.34, 0.5, 0.30)
	draw_line(p, p + Vector2(0, -34), g, 6.0)
	draw_line(p + Vector2(0, -14), p + Vector2(-10, -14), g, 4.0)
	draw_line(p + Vector2(-10, -14), p + Vector2(-10, -24), g, 4.0)
	draw_line(p + Vector2(0, -22), p + Vector2(9, -22), g, 4.0)
	draw_line(p + Vector2(9, -22), p + Vector2(9, -30), g, 4.0)


func _compass(c: Vector2) -> void:
	draw_circle(c, 22.0, Color(0.80, 0.70, 0.48))
	draw_arc(c, 22.0, 0, TAU, 28, Color(0.40, 0.27, 0.14), 2.0)
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		draw_line(c, c + Vector2.RIGHT.rotated(a - PI * 0.5) * 18.0, Color(0.40, 0.27, 0.14), 1.0)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -20), c + Vector2(-5, 0), c + Vector2(5, 0)]), Color(0.70, 0.22, 0.16))
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, 20), c + Vector2(-5, 0), c + Vector2(5, 0)]), Color(0.30, 0.22, 0.14))
	_text(c + Vector2(-4, -24), "N", 14, Color(0.35, 0.20, 0.10))


func _dashed(a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void:
	var d := a.distance_to(b)
	if d < 0.01:
		return
	var dir := (b - a) / d
	var t := 0.0
	while t < d:
		var t2: float = min(t + dash, d)
		draw_line(a + dir * t, a + dir * t2, col, w)
		t += dash * 2.0


# --- Pastilles de ville (boutons) ---

func _make_pin(idx: int) -> Button:
	var t := GameManager.town_def(idx)
	var lvl := int(t.get("level", 0))
	var unlocked := GameManager.town_unlocked(idx)
	var done := lvl >= 1 and SaveManager.levels_unlocked > lvl
	var b := Button.new()
	b.custom_minimum_size = PIN
	b.size = PIN
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color(1, 1, 0.92))
	b.add_theme_color_override("font_outline_color", Color(0.10, 0.06, 0.03))
	b.add_theme_constant_override("outline_size", 4)
	var bg: Color
	var border: Color
	var status: String
	if lvl < 1:
		bg = Color(0.40, 0.38, 0.36, 0.95); border = Color(0.6, 0.58, 0.55); status = "🔒 " + str(t["tag"])
	elif not unlocked:
		bg = Color(0.38, 0.30, 0.24, 0.95); border = Color(0.6, 0.5, 0.4)
		status = "🔒 Réussis la ville précédente"
	elif done:
		bg = Color(0.22, 0.42, 0.22, 0.96); border = Color(0.5, 0.85, 0.45); status = "✓ Banque dévalisée"
	else:
		bg = Color(0.46, 0.26, 0.12, 0.96); border = Color(0.95, 0.78, 0.30); status = "▶ " + str(t["tag"])
	b.text = "%s\n%s" % [str(t["name"]), status]
	_style(b, bg, border)
	if unlocked:
		b.pressed.connect(func() -> void: GameManager.travel_to_town(idx))
	else:
		b.disabled = true
	return b


func _style(b: Button, bg: Color, border: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = border
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("disabled", sb)
	var hb: StyleBoxFlat = sb.duplicate()
	hb.bg_color = bg.lightened(0.10)
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("pressed", hb)


# --- Petits utilitaires ---

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _text(pos: Vector2, s: String, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
