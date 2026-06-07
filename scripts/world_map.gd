extends Control
## world_map.gd
## Carte du monde "parchemin" du Far West, PROCÉDURALE : ~20 villes (générées par
## GameManager) réparties le long d'une piste sinueuse à travers des biomes
## (désert → canyon → plaines → neige → nuit). Marqueurs cliquables, déblocage
## séquentiel. UI construite en code (desktop + mobile tactile).

const MARGIN := Vector2(0.055, 0.165)    # marges normalisées autour de la zone carte
const TAP := Vector2(48.0, 48.0)         # cible tactile par ville

var _t := 0.0
var _btns: Array[Dictionary] = []        # { "idx", "btn" }


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var done: int = SaveManager.towns_unlocked - 1
	var total: int = GameManager.TOWNS.size()
	# Titre + progression.
	var title := _label("CARTE DU TERRITOIRE", 32, Color(0.36, 0.20, 0.10))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE); title.position = Vector2(0, 10)
	add_child(title)
	var sub := _label("%d villes à dévaliser — suis la piste, dévalise chaque banque" % total,
			17, Color(0.42, 0.28, 0.16))
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE); sub.position = Vector2(0, 48)
	add_child(sub)
	var prog := _label("Villes conquises : %d / %d   ·   Magot : %d $   ·   Notoriété : %s" % [
			maxi(0, done), total, SaveManager.total_money, _stars(SaveManager.notoriety)], 17, Color(0.30, 0.20, 0.12))
	prog.set_anchors_preset(Control.PRESET_TOP_WIDE); prog.position = Vector2(0, 74)
	add_child(prog)
	# Cibles tactiles invisibles sur chaque ville débloquée (marqueurs dessinés en _draw).
	for i in range(1, total + 1):
		if not GameManager.town_unlocked(i):
			continue
		var b := Button.new()
		b.custom_minimum_size = TAP
		b.size = TAP
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = str(GameManager.town_def(i)["name"])
		var sb := StyleBoxEmpty.new()
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_stylebox_override("focus", sb)
		var idx := i
		b.pressed.connect(func() -> void: GameManager.travel_to_town(idx))
		add_child(b)
		_btns.append({"idx": i, "btn": b})
	# Boutons bas.
	var back := Button.new()
	back.text = "← Menu"; back.add_theme_font_size_override("font_size", 20)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT); back.position = Vector2(20, -62)
	back.custom_minimum_size = Vector2(150, 46)
	back.pressed.connect(func() -> void: GameManager.goto_main_menu())
	add_child(back)
	var quick := Button.new()
	quick.text = "⚡ Niveau rapide"; quick.add_theme_font_size_override("font_size", 18)
	quick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT); quick.position = Vector2(-210, -62)
	quick.custom_minimum_size = Vector2(190, 46)
	quick.pressed.connect(func() -> void: GameManager.goto_level_select())
	add_child(quick)

	resized.connect(_layout)
	_layout()
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# --- Géométrie ---

func _inner() -> Rect2:
	var m := Vector2(size.x * MARGIN.x, size.y * MARGIN.y)
	return Rect2(m, size - m * 2.0)


func _pt(idx: int) -> Vector2:
	var p: Array = GameManager.town_def(idx)["pos"]
	var r := _inner()
	return r.position + Vector2(float(p[0]) * r.size.x, float(p[1]) * r.size.y)


func _layout() -> void:
	for d in _btns:
		(d["btn"] as Button).position = _pt(d["idx"]) - TAP * 0.5
	queue_redraw()


# --- Rendu ---

func _draw() -> void:
	var inner := _inner()
	# Fond parchemin.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.86, 0.76, 0.55))
	# Régions de biome (bandes verticales teintées) qui suivent la piste.
	_biome_bands(inner)
	# Voile parchemin pour unifier.
	draw_rect(inner, Color(0.86, 0.76, 0.52, 0.18))
	# Reliefs : montagnes enneigées dans la région froide (droite).
	for k in range(5):
		var mx := lerpf(inner.position.x + inner.size.x * 0.78, inner.end.x - 20, float(k) / 4.0)
		_mountain(Vector2(mx, inner.position.y + 60.0 + (k % 2) * 22.0), 60.0)
	# Sapins (région neige).
	for k in range(4):
		_pine(Vector2(lerpf(inner.position.x + inner.size.x * 0.80, inner.end.x - 30, float(k) / 3.0),
				inner.get_center().y + 40.0 + (k % 2) * 30.0))
	# Cactus (désert, gauche) + rochers (canyon).
	for cp in [[0.05, 0.30], [0.10, 0.78], [0.20, 0.55]]:
		_cactus(_inner_pt(cp))
	for rp in [[0.34, 0.30], [0.40, 0.80]]:
		_rock(_inner_pt(rp))
	# Rivière dans les plaines.
	var river := PackedVector2Array()
	for k in range(13):
		var u := float(k) / 12.0
		river.append(Vector2(lerpf(inner.position.x + inner.size.x * 0.46, inner.position.x + inner.size.x * 0.66, u),
				inner.end.y - 40.0 + sin(u * 6.0) * 22.0))
	draw_polyline(river, Color(0.45, 0.60, 0.70, 0.7), 5.0)
	# Cadre brûlé.
	for i in range(3):
		var inset := 6.0 + i * 5.0
		draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0),
				Color(0.40, 0.27, 0.14, 0.5 - i * 0.12), false, 3.0)

	# Piste sinueuse reliant toutes les villes.
	var n := GameManager.TOWNS.size()
	var pts := PackedVector2Array()
	for i in range(1, n + 1):
		pts.append(_pt(i))
	# Tracé large (terre battue) puis pointillés.
	if pts.size() >= 2:
		draw_polyline(pts, Color(0.66, 0.52, 0.34, 0.55), 9.0)
		for i in range(pts.size() - 1):
			var unlocked := (i + 2) <= SaveManager.towns_unlocked
			_dashed(pts[i], pts[i + 1],
					Color(0.45, 0.30, 0.16, 0.95) if unlocked else Color(0.45, 0.30, 0.16, 0.45),
					3.0, 11.0)

	# Marqueurs de ville + noms.
	for i in range(1, n + 1):
		_marker(i)

	# Pion courrier qui chevauche jusqu'à la frontière.
	var fidx := clampi(SaveManager.towns_unlocked, 1, n)
	if fidx >= 2 and pts.size() >= fidx:
		var segs := fidx - 1
		var f := fmod(_t * 0.05, 1.0) * segs
		var i := clampi(int(f), 0, segs - 1)
		_pawn(pts[i].lerp(pts[i + 1], f - i))
	elif pts.size() >= 1:
		_pawn(pts[0])

	# Rose des vents.
	_compass(Vector2(inner.end.x - 44, inner.position.y + 54))


func _inner_pt(p: Array) -> Vector2:
	var r := _inner()
	return r.position + Vector2(float(p[0]) * r.size.x, float(p[1]) * r.size.y)


## Marqueur d'une ville (état : conquise / frontière / verrouillée) + nom.
func _marker(idx: int) -> void:
	var c := _pt(idx)
	var unlocked := GameManager.town_unlocked(idx)
	var done := idx < SaveManager.towns_unlocked
	var frontier := idx == SaveManager.towns_unlocked
	var col: Color
	var rad := 11.0
	if done:
		col = Color(0.28, 0.55, 0.28)
	elif frontier:
		col = Color(0.95, 0.78, 0.28)
		rad = 12.0 + sin(_t * 4.0) * 2.0
		# Halo pulsé "tu es ici / à conquérir".
		draw_circle(c, rad + 9.0, Color(1.0, 0.85, 0.35, 0.18))
	elif unlocked:
		col = Color(0.70, 0.45, 0.22)
	else:
		col = Color(0.46, 0.44, 0.42)
		rad = 8.0
	draw_circle(c + Vector2(1, 2), rad, Color(0, 0, 0, 0.20))     # ombre
	draw_circle(c, rad, col)
	draw_arc(c, rad, 0, TAU, 20, col.darkened(0.35), 2.0)
	draw_circle(c, rad * 0.45, Color(1, 1, 1, 0.85))
	if done:
		# Petit check.
		draw_line(c + Vector2(-4, 0), c + Vector2(-1, 4), Color(0.15, 0.35, 0.15), 2.0)
		draw_line(c + Vector2(-1, 4), c + Vector2(5, -4), Color(0.15, 0.35, 0.15), 2.0)
	elif not unlocked:
		_text_c("🔒", c + Vector2(0, 4), 12, Color(0.9, 0.9, 0.9))
	# Nom (alterné au-dessus/au-dessous pour limiter les chevauchements).
	var t := GameManager.town_def(idx)
	var below := (idx % 2 == 0)
	var off := Vector2(0, 26.0 if below else -16.0)
	var nm_col: Color = Color(0.25, 0.16, 0.08) if unlocked else Color(0.40, 0.36, 0.32)
	_text_c(str(t["name"]), c + off, 12, nm_col)
	if frontier:
		_text_c(str(t["tag"]), c + off + Vector2(0, 13.0 if below else -13.0), 10,
				Color(0.55, 0.36, 0.12))


# --- Décor de carte ---

func _biome_bands(inner: Rect2) -> void:
	# x-fractions des frontières (alignées sur GameManager._biome_for via x≈t).
	var cols := [Color(0.88, 0.78, 0.55), Color(0.84, 0.60, 0.44), Color(0.79, 0.82, 0.56),
			Color(0.86, 0.90, 0.95), Color(0.60, 0.60, 0.74)]
	var bounds := [0.0, 0.26, 0.43, 0.59, 0.76, 1.0]
	for i in range(cols.size()):
		var x0 := inner.position.x + inner.size.x * float(bounds[i])
		var x1 := inner.position.x + inner.size.x * float(bounds[i + 1])
		draw_rect(Rect2(Vector2(x0, inner.position.y), Vector2(x1 - x0, inner.size.y)), cols[i])


func _mountain(p: Vector2, w: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-w, w), p, p + Vector2(w, w)]), Color(0.62, 0.62, 0.66))
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-12, 14), p, p + Vector2(12, 14)]), Color(0.96, 0.97, 1.0))


func _pine(p: Vector2) -> void:
	draw_line(p, p + Vector2(0, -6), Color(0.35, 0.24, 0.14), 3.0)
	for k in range(3):
		var yy := -6.0 - k * 7.0
		var ww := 9.0 - k * 2.5
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-ww, yy), p + Vector2(0, yy - 10), p + Vector2(ww, yy)]),
			Color(0.20, 0.42, 0.26))


func _cactus(p: Vector2) -> void:
	var g := Color(0.34, 0.5, 0.30)
	draw_line(p, p + Vector2(0, -30), g, 6.0)
	draw_line(p + Vector2(0, -12), p + Vector2(-9, -12), g, 4.0)
	draw_line(p + Vector2(-9, -12), p + Vector2(-9, -21), g, 4.0)
	draw_line(p + Vector2(0, -20), p + Vector2(8, -20), g, 4.0)
	draw_line(p + Vector2(8, -20), p + Vector2(8, -27), g, 4.0)


func _rock(p: Vector2) -> void:
	draw_colored_polygon(_ellipse(p, 16, 9), Color(0.62, 0.42, 0.30))
	draw_colored_polygon(_ellipse(p + Vector2(8, -5), 10, 7), Color(0.70, 0.48, 0.34))


func _compass(c: Vector2) -> void:
	draw_circle(c, 22.0, Color(0.80, 0.70, 0.48))
	draw_arc(c, 22.0, 0, TAU, 28, Color(0.40, 0.27, 0.14), 2.0)
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		draw_line(c, c + Vector2.RIGHT.rotated(a) * 18.0, Color(0.40, 0.27, 0.14), 1.0)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -20), c + Vector2(-5, 0), c + Vector2(5, 0)]), Color(0.70, 0.22, 0.16))
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, 20), c + Vector2(-5, 0), c + Vector2(5, 0)]), Color(0.30, 0.22, 0.14))
	_text_c("N", c + Vector2(0, -26), 13, Color(0.35, 0.20, 0.10))


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


func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


# --- Texte / labels ---

## Petit cavalier animé sur la piste.
func _pawn(p: Vector2) -> void:
	draw_circle(p + Vector2(2, 5), 6.0, Color(0, 0, 0, 0.18))
	draw_circle(p + Vector2(0, -1), 5.0, Color(0.46, 0.30, 0.18))      # monture
	draw_circle(p + Vector2(0, -8), 3.2, Color(0.86, 0.66, 0.46))      # tête
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-5, -10), p + Vector2(5, -10), p + Vector2(0, -15)]), Color(0.30, 0.20, 0.12))


func _stars(n: int) -> String:
	if n <= 0:
		return "—"
	var s := ""
	for i in range(mini(n, 12)):
		s += "★"
	return s


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _text_c(s: String, center: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, center - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
