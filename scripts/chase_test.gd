extends Node2D
## chase_test.gd
## Banc d'essai du lot 17 : valide `RelativeChaseController` SANS contenu
## train/diligence. Une cible rectangulaire (le "convoi") avance en continu ; la
## caméra la suit (le monde défile) ; le joueur à cheval se déplace par rapport à
## elle (avancer/reculer, gauche/droite) et peut tirer. Aucune dépendance aux
## systèmes de mission.

const TARGET_SPEED := 300.0     # la cible avance toute seule
const BULLET_SPEED := 900.0

var _chase := RelativeChaseController.new()
var _horse := HorseController.new()
var _target_pos := Vector2(0, 0)
var _track_dir := Vector2.RIGHT
var _player_pos := Vector2.ZERO
var _facing := Vector2.RIGHT
var _ride := 0.0
var _bullets: Array[Dictionary] = []
var _fire_cd := 0.0
var _was_fire := false
var _scale := 1.6
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Iso.top_down = true
	_horse.mounted = true   # on est en poursuite, donc à cheval
	_rng.randomize()
	_player_pos = _chase.player_world(_target_pos, _track_dir)
	var vp := get_viewport_rect().size
	_scale = clampf(minf(vp.x, vp.y) / 460.0, 1.2, 2.4)
	scale = Vector2(_scale, _scale)


func _process(delta: float) -> void:
	Iso.top_down = true
	# La cible avance en continu (légère ondulation de cap pour montrer le perp).
	_track_dir = Vector2.RIGHT.rotated(sin(_target_pos.x * 0.0009) * 0.18)
	_target_pos += _track_dir * TARGET_SPEED * delta
	# Déplacement RELATIF du joueur depuis l'entrée (alignée écran).
	var input := InputManager.get_move_vector()
	_chase.update(delta, input)
	var new_pos := _chase.player_world(_target_pos, _track_dir)
	var move := new_pos - _player_pos
	if move.length() > 1.0:
		_facing = move.normalized()
	_player_pos = new_pos
	_ride += delta * 12.0
	# Tir vers l'avant de la course.
	_fire_cd = maxf(0.0, _fire_cd - delta)
	var fire := InputManager.is_fire_pressed()
	if fire and _fire_cd <= 0.0:
		_shoot()
		_fire_cd = 0.25
	_was_fire = fire
	# Avance des balles.
	var alive: Array[Dictionary] = []
	for b in _bullets:
		b["pos"] += b["vel"] * delta
		b["life"] -= delta
		if b["life"] > 0.0:
			alive.append(b)
	_bullets = alive
	# Caméra : suit la cible -> le monde défile.
	var vp := get_viewport_rect().size
	position = vp * 0.5 - _target_pos * _scale
	queue_redraw()


func _shoot() -> void:
	var dir := _track_dir.normalized()
	_bullets.append({"pos": _player_pos + dir * 18.0, "vel": dir * BULLET_SPEED, "life": 0.8})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		GameManager.goto_main_menu()


func _draw() -> void:
	_draw_ground()
	_draw_lane()
	# Cible (convoi stand-in) : rectangle orienté selon la course.
	_draw_target()
	# Balles (traceurs).
	for b in _bullets:
		var p: Vector2 = b["pos"]
		var d: Vector2 = (b["vel"] as Vector2).normalized()
		draw_line(p - d * 16.0, p, Color(1, 0.9, 0.4, 0.5), 3.0)
		draw_circle(p, 3.0, Color(1, 0.95, 0.5))
	_draw_rider()
	_draw_hud()


func _draw_ground() -> void:
	# Bandes perpendiculaires à la course pour donner la sensation de vitesse.
	var perp := Vector2(-_track_dir.y, _track_dir.x)
	var step := 120.0
	var base := floorf(_target_pos.x / step) * step
	for i in range(-6, 14):
		var x := base + i * step
		var c := Color(0.78, 0.62, 0.42) if int(roundf(x / step)) % 2 == 0 else Color(0.73, 0.57, 0.38)
		var center := Vector2(x, _target_pos.y)
		var a := center + perp * 900.0 - _track_dir * (step * 0.5)
		var bb := center - perp * 900.0 - _track_dir * (step * 0.5)
		var cc := center - perp * 900.0 + _track_dir * (step * 0.5)
		var dd := center + perp * 900.0 + _track_dir * (step * 0.5)
		draw_colored_polygon(PackedVector2Array([a, dd, cc, bb]), c)


func _draw_lane() -> void:
	# Limites de la bande jouable (latérale) le long de la course.
	var perp := Vector2(-_track_dir.y, _track_dir.x)
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for k in range(-4, 12):
			var along := _target_pos + _track_dir * (k * 80.0 - 200.0)
			pts.append(along + perp * (side * RelativeChaseController.LANE_HALF))
		draw_polyline(pts, Color(0.95, 0.85, 0.3, 0.35), 2.0)


func _draw_target() -> void:
	var dir := _track_dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var hl := 60.0
	var hw := 34.0
	var c := _target_pos
	var poly := PackedVector2Array([
		c - dir * hl - perp * hw, c + dir * hl - perp * hw,
		c + dir * hl + perp * hw, c - dir * hl + perp * hw])
	draw_colored_polygon(poly, Color(0.45, 0.30, 0.18))
	draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]),
			Color(0.2, 0.13, 0.08), 3.0)
	# Coffre stylisé au centre (cible d'interaction).
	draw_circle(c, 12.0, Color(0.9, 0.78, 0.32))
	_text(c + Vector2(0, -hw - 18.0), "CONVOI", 14, Color(1, 0.95, 0.7))


func _draw_rider() -> void:
	var base := _player_pos
	var g: float = _horse.gallop if _horse.gallop > 0.0 else 1.0
	# Le galop est "permanent" en poursuite (la monture court).
	var bob := sin(_ride) * 2.0
	# Poussière derrière.
	var back := -_track_dir.normalized() * 18.0
	for i in range(2):
		var pp := base + back + Vector2(_rng.randf_range(-7, 7), _rng.randf_range(-2, 6))
		draw_circle(pp, _rng.randf_range(3.0, 6.0), Color(0.7, 0.6, 0.45, 0.25))
	draw_colored_polygon(_shadow(base, 22.0), Color(0, 0, 0, 0.2))
	var flip := -1.0 if _facing.x > 0.1 else 1.0
	_horse_body(base + Vector2(0, bob), flip)
	CharacterArt.draw_person(self, base + Vector2(0, -17 + bob), _facing,
			CharacterArt.hero_palette(), false, false, 0.0, 0.0, 0.0)


func _draw_hud() -> void:
	var vp := get_viewport_rect().size
	var origin := -position / _scale
	var top := origin + Vector2(vp.x * 0.5 / _scale, 14.0 / _scale)
	var msg := "POURSUITE — flèches: avancer/reculer + gauche/droite · clic: tirer · Échap: quitter"
	_text(top, msg, int(13.0 / _scale), Color(1, 0.97, 0.85))
	var st := ""
	var col := Color(1, 1, 1)
	if _chase.caught_up():
		st = "À HAUTEUR DU CONVOI !"
		col = Color(0.5, 1.0, 0.5)
	elif _chase.is_distanced():
		st = "DISTANCÉ — rattrape !"
		col = Color(1.0, 0.4, 0.3)
	else:
		st = "Écart: %d" % int(_chase.gap())
		col = Color(1, 0.9, 0.6)
	_text(top + Vector2(0, 22.0 / _scale), st, int(18.0 / _scale), col)


# --- primitives ---

func _horse_body(base: Vector2, flip: float) -> void:
	var body := Color(0.36, 0.23, 0.13)
	var dark := body.darkened(0.28)
	for dx in [-9.0, -3.0, 4.0, 10.0]:
		draw_line(base + Vector2(dx * flip, -12), base + Vector2((dx + 1.0) * flip, 2), dark, 3.0)
	var bl := base + Vector2(-12 * flip, -16)
	var brr := base + Vector2(12 * flip, -16)
	draw_line(bl, brr, body, 14.0)
	draw_circle(bl, 7.0, body)
	draw_circle(brr, 7.0, body)
	draw_line(brr + Vector2(3 * flip, -3), base + Vector2(18 * flip, 3), dark, 3.0)
	var neck := bl + Vector2(1 * flip, -3)
	var head := bl + Vector2(-11 * flip, -16)
	draw_line(neck, head, body, 7.0)
	draw_circle(head, 4.5, body)
	draw_line(head, head + Vector2(-5 * flip, 2), body, 5.0)


func _shadow(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-r, 0), c + Vector2(0, -r * 0.5),
			c + Vector2(r, 0), c + Vector2(0, r * 0.5)])


func _text(pos: Vector2, s: String, size_px: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var base := pos - Vector2(w * 0.5, 0)
	draw_string(font, base + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(0, 0, 0, 0.7))
	draw_string(font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
