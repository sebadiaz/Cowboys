extends Control
## atmosphere.gd
## Calque d'ambiance cinématographique plein écran (screen-space, par-dessus le
## monde, sous l'UI). Pur visuel, isolé et réutilisable : RAIS DE LUMIÈRE dorés,
## gros halo de soleil, poussières d'or qui dansent, oiseaux au loin, et un cycle
## jour → golden hour → nuit étoilée piloté LOCALEMENT (toujours visible).

const CYCLE := 150.0           # durée d'un cycle jour/nuit (s)

var _t := 0.0
var _day := 0.30               # 0..1 : 0/1 = nuit, 0.5 = plein jour (départ golden)
var _motes: Array[Dictionary] = []
var _birds: Array[Dictionary] = []
var _stars: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	for i in range(95):
		_motes.append({"p": Vector2(_rng.randf(), _rng.randf()), "r": _rng.randf_range(1.2, 3.6),
			"spd": _rng.randf_range(0.015, 0.05), "sway": _rng.randf_range(0.4, 1.6), "ph": _rng.randf() * TAU})
	for i in range(5):
		_birds.append({"p": Vector2(_rng.randf(), _rng.randf_range(0.08, 0.28)),
			"spd": _rng.randf_range(0.03, 0.06), "ph": _rng.randf() * TAU})
	for i in range(90):
		_stars.append({"p": Vector2(_rng.randf(), _rng.randf_range(0.0, 0.55)),
			"r": _rng.randf_range(0.7, 1.8), "ph": _rng.randf() * TAU})


func _process(delta: float) -> void:
	_t += delta
	_day = fposmod(_day + delta / CYCLE, 1.0)
	for m in _motes:
		var p: Vector2 = m["p"]
		p.y -= float(m["spd"]) * delta
		p.x += sin(_t * float(m["sway"]) + float(m["ph"])) * 0.35 * delta
		if p.y < -0.02:
			p.y = 1.02
			p.x = _rng.randf()
		m["p"] = p
	for b in _birds:
		var bp: Vector2 = b["p"]
		bp.x += float(b["spd"]) * delta
		if bp.x > 1.12:
			bp.x = -0.12
			bp.y = _rng.randf_range(0.08, 0.28)
		b["p"] = bp
	queue_redraw()


## Intensité de nuit 0..1 (nuit autour de _day≈0 et ≈1).
func _night() -> float:
	return clampf(pow((cos(_day * TAU) + 1.0) * 0.5, 1.4), 0.0, 1.0)


## Chaleur "golden hour" 0..1 (max au lever/coucher).
func _golden() -> float:
	return clampf(1.0 - absf(sin(_day * TAU)) , 0.0, 1.0)


func _draw() -> void:
	var s := size if size.x > 1.0 else get_viewport_rect().size
	var night := _night()
	var gold := _golden()
	var day := 1.0 - night
	var sun := Vector2(s.x * 0.80, s.y * 0.15)

	# --- Rais de lumière (god rays) depuis le soleil ---
	var ray_a := 0.07 * day + 0.05 * gold
	for i in range(7):
		var base := PI * 0.62 + i * 0.10 + sin(_t * 0.15 + i) * 0.015
		var spread := 0.022 + 0.01 * sin(_t * 0.2 + i * 1.7)
		var d1 := Vector2.RIGHT.rotated(base - spread)
		var d2 := Vector2.RIGHT.rotated(base + spread)
		var L := s.length() * 1.3
		draw_colored_polygon(PackedVector2Array([sun, sun + d1 * L, sun + d2 * L]),
				Color(1.0, 0.82, 0.45, ray_a * (0.6 + 0.4 * sin(_t * 0.5 + i))))

	# --- Gros halo de soleil ---
	for g in range(9):
		draw_circle(sun, 230.0 - g * 24.0, Color(1.0, 0.84, 0.48, 0.055 * day))
	draw_circle(sun, 34.0, Color(1.0, 0.94, 0.7, 0.5 * day))

	# --- Dégradé chaud qui descend du haut ---
	var bands := 16
	for i in range(bands):
		var f := float(i) / bands
		draw_rect(Rect2(0, f * s.y * 0.6, s.x, s.y * 0.6 / bands + 1.0),
				Color(1.0, 0.66 + 0.1 * gold, 0.34, 0.07 * (1.0 - f) * day))

	# --- Nuit : voile bleu + étoiles + lune ---
	if night > 0.03:
		draw_rect(Rect2(0, 0, s.x, s.y), Color(0.07, 0.11, 0.30, 0.40 * night))
		for st in _stars:
			var sp: Vector2 = (st["p"] as Vector2) * s
			var tw := 0.5 + 0.5 * sin(_t * 2.5 + float(st["ph"]))
			draw_circle(sp, float(st["r"]), Color(1, 1, 0.93, tw * night))
		var moon := Vector2(s.x * 0.18, s.y * 0.17)
		draw_circle(moon, 30.0, Color(0.96, 0.96, 0.86, night))
		draw_circle(moon, 36.0, Color(0.9, 0.9, 1.0, 0.18 * night))
		draw_circle(moon + Vector2(11, -5), 27.0, Color(0.07, 0.11, 0.30, night))

	# --- Oiseaux lointains ---
	for b in _birds:
		var bp: Vector2 = (b["p"] as Vector2) * s
		var flap := sin(_t * 6.0 + float(b["ph"])) * 4.0
		var c := Color(0.15, 0.10, 0.08, 0.45 * day)
		draw_line(bp + Vector2(-8, flap), bp, c, 1.6)
		draw_line(bp, bp + Vector2(8, flap), c, 1.6)

	# --- Poussières d'or qui dansent ---
	for m in _motes:
		var mp: Vector2 = (m["p"] as Vector2) * s
		var tw2 := 0.4 + 0.4 * sin(_t * 2.0 + float(m["ph"]))
		var a := tw2 * (0.7 - night * 0.35)
		var rr := float(m["r"])
		draw_circle(mp, rr + 2.5, Color(1.0, 0.85, 0.5, a * 0.25))    # halo
		draw_circle(mp, rr, Color(1.0, 0.93, 0.66, a))               # cœur

	# --- Vignette chaude légère ---
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.18, 0.09, 0.04, 0.12), false, 60.0)
