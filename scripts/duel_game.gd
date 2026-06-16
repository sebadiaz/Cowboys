extends Control
class_name DuelGame
## duel_game.gd — DUEL AU PISTOLET (quick-draw) façon high-noon.
## Mini-jeu de réflexe autonome : on attend le SIGNAL puis on DÉGAINE le plus vite
## possible. Tirer trop tôt = faux départ (défaite) ; trop lent = l'adversaire
## t'abat. Gagner paie une prime (bonus si dégaine éclair). Overlay screen-space
## posé sous une CanvasLayer (par le saloon), entrées propres, tout dessiné.

signal closed

enum State { INTRO, WAIT, DRAW, RESULT }

var _state: int = State.INTRO
var _t := 0.0
var _wait_left := 0.0           # délai avant le signal "TIRE !"
var _draw_t := 0.0              # temps écoulé depuis le signal
var _react := -1.0             # temps de réaction du joueur (s)
var _rival_react := 0.5        # seuil de l'adversaire (s)
var _won := false
var _result := ""
var _result_col := Color.WHITE
var _bounty := 0
var _penalty := 0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()
var _btns: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	# Adversaire plus rapide quand la notoriété grimpe (plus dur).
	_rival_react = clampf(0.52 - SaveManager.notoriety * 0.02, 0.30, 0.52)
	_bounty = 220 + SaveManager.notoriety * 70
	_penalty = mini(120, SaveManager.total_money)
	_build_buttons()
	_refresh_buttons()


func _build_buttons() -> void:
	for spec in [["go", "PRÊT"], ["fire", "DÉGAINE !"], ["again", "REVANCHE"], ["quit", "QUITTER"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(_on_button.bind(spec[0]))
		add_child(b)
		_btns[spec[0]] = b


func _layout_buttons() -> void:
	var vp := size if size.x > 1.0 else get_viewport_rect().size
	var row: Array = []
	match _state:
		State.INTRO: row = ["go", "quit"]
		State.WAIT, State.DRAW: row = ["fire"]
		State.RESULT: row = ["again", "quit"]
	var w := 240.0
	var h := 64.0
	var total := row.size() * w + maxf(0.0, row.size() - 1) * 18.0
	var x := vp.x * 0.5 - total * 0.5
	for n in _btns:
		_btns[n].visible = n in row
	for n in row:
		var b: Button = _btns[n]
		b.size = Vector2(w, h)
		b.position = Vector2(x, vp.y - 96.0)
		x += w + 18.0


func _refresh_buttons() -> void:
	_layout_buttons()


func _on_button(which: String) -> void:
	match which:
		"go": _begin()
		"fire": _fire()
		"again": _reset()
		"quit": _close()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match _state:
			State.INTRO:
				if event.keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]: _begin()
				elif event.keycode == KEY_ESCAPE: _close()
			State.WAIT, State.DRAW:
				if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_F]: _fire()
			State.RESULT:
				if event.keycode in [KEY_ENTER, KEY_SPACE]: _reset()
				elif event.keycode == KEY_ESCAPE: _close()
		get_viewport().set_input_as_handled()


# --- Logique ---

func _begin() -> void:
	if _state != State.INTRO:
		return
	_state = State.WAIT
	_wait_left = _rng.randf_range(1.4, 3.6)
	_draw_t = 0.0
	_react = -1.0
	_refresh_buttons()


func _fire() -> void:
	if _state == State.WAIT:
		# Faux départ : tiré avant le signal.
		_resolve(false, "FAUX DÉPART ! Tu dégaines trop tôt")
	elif _state == State.DRAW:
		_react = _draw_t
		_resolve(true, "TOUCHÉ ! Dégaine en %.2f s" % _react)


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 3.0)
	if _state == State.WAIT:
		_wait_left -= delta
		if _wait_left <= 0.0:
			_state = State.DRAW
			_draw_t = 0.0
			_flash = 1.0
			AudioManager.play("click")
	elif _state == State.DRAW:
		_draw_t += delta
		if _draw_t >= _rival_react and _react < 0.0:
			# L'adversaire a dégainé le premier.
			_resolve(false, "TROP LENT ! Il t'a devancé")
	queue_redraw()


func _resolve(player_fired_in_time: bool, msg: String) -> void:
	_won = player_fired_in_time
	_result = msg
	_flash = 1.0
	if _won:
		var fast_bonus := int(clampf(_rival_react - _react, 0.0, 0.4) * 800.0)
		var total := _bounty + fast_bonus
		SaveManager.refund(total)
		_result_col = Color(0.6, 1.0, 0.6)
		_result += "  +%d $" % total
		AudioManager.play("win", -2.0)
	else:
		SaveManager.spend(_penalty)
		_result_col = Color(1, 0.45, 0.35)
		if _penalty > 0:
			_result += "  −%d $ (médecin)" % _penalty
		AudioManager.play("lose", -2.0)
	AudioManager.play("shot", -4.0)
	_state = State.RESULT
	_refresh_buttons()


func _reset() -> void:
	_state = State.INTRO
	_react = -1.0
	_won = false
	_result = ""
	_penalty = mini(120, SaveManager.total_money)
	_refresh_buttons()


func _close() -> void:
	closed.emit()
	queue_free()


# --- Rendu ---

func _draw() -> void:
	var vp := size if size.x > 1.0 else get_viewport_rect().size
	# Ciel crépusculaire + sol.
	for i in range(10):
		var f := float(i) / 10.0
		draw_rect(Rect2(0, f * vp.y * 0.6, vp.x, vp.y * 0.06 + 1.0),
				Color(0.95 - f * 0.3, 0.6 - f * 0.2, 0.3 + f * 0.1).lerp(Color(0.2, 0.18, 0.3), f * 0.4))
	draw_rect(Rect2(0, vp.y * 0.6, vp.x, vp.y * 0.4), Color(0.62, 0.46, 0.28))
	var sun := Vector2(vp.x * 0.5, vp.y * 0.30)
	draw_circle(sun, 70.0, Color(1.0, 0.85, 0.5, 0.9))
	draw_circle(sun, 120.0, Color(1.0, 0.8, 0.45, 0.15))

	var gy := vp.y * 0.6
	_draw_gunman(Vector2(vp.x * 0.22, gy), 1.0, Color(0.95, 0.92, 0.8), _state == State.RESULT and _won)
	_draw_gunman(Vector2(vp.x * 0.78, gy), -1.0, Color(0.3, 0.28, 0.34), _state == State.RESULT and not _won)

	# Éclair de tir.
	if _flash > 0.0 and _state == State.RESULT:
		var shooter := Vector2(vp.x * 0.22, gy - 30) if _won else Vector2(vp.x * 0.78, gy - 30)
		draw_circle(shooter, 16.0 * _flash, Color(1, 0.95, 0.6, _flash))

	var cx := vp.x * 0.5
	_text(Vector2(cx, vp.y * 0.12), "★ DUEL AU PISTOLET ★", 32, Color(0.2, 0.15, 0.1), true)
	match _state:
		State.INTRO:
			_text(Vector2(cx, vp.y * 0.40), "Attends le signal, puis DÉGAINE !", 22, Color(0.15, 0.1, 0.08), true)
			_text(Vector2(cx, vp.y * 0.46), "Tire trop tôt = faux départ. Prime : %d $" % _bounty, 17, Color(0.2, 0.15, 0.1), true)
		State.WAIT:
			# Tension : grosse police rouge "..." qui palpite.
			var pulse := 0.5 + 0.5 * sin(_t * 5.0)
			_text(Vector2(cx, vp.y * 0.42), "…", 60, Color(0.2, 0.1, 0.1, 0.5 + 0.5 * pulse), true)
			_text(Vector2(cx, vp.y * 0.50), "ATTENDS…", 22, Color(0.6, 0.2, 0.15), true)
		State.DRAW:
			var sc := 1.0 + _flash * 0.6
			_text(Vector2(cx, vp.y * 0.42), "TIRE !", int(72 * sc), Color(1.0, 0.2, 0.15), true)
		State.RESULT:
			_text(Vector2(cx, vp.y * 0.42), _result, 26, _result_col, true)
			_text(Vector2(cx, vp.y * 0.48), "Butin : %d $" % SaveManager.total_money, 18, Color(0.2, 0.15, 0.1), true)


func _draw_gunman(base: Vector2, face: float, body_col: Color, victorious: bool) -> void:
	var col := body_col if victorious or _state != State.RESULT else body_col.darkened(0.1)
	draw_colored_polygon(PackedVector2Array([base + Vector2(-18, 0), base + Vector2(0, -7),
			base + Vector2(18, 0), base + Vector2(0, 7)]), Color(0, 0, 0, 0.22))
	# À terre si vaincu.
	if _state == State.RESULT and not victorious:
		draw_circle(base + Vector2(0, -6), 12.0, col)
		draw_line(base, base + Vector2(34 * face, -4), col, 10.0)
		return
	# Corps + tête + chapeau.
	draw_line(base, base + Vector2(0, -42), col, 14.0)
	draw_circle(base + Vector2(0, -52), 9.0, Color(0.85, 0.66, 0.48))
	draw_rect(Rect2(base + Vector2(-13, -64), Vector2(26, 6)), Color(0.2, 0.13, 0.08))
	draw_rect(Rect2(base + Vector2(-8, -72), Vector2(16, 9)), Color(0.2, 0.13, 0.08))
	# Bras vers le holster (ou tendu en tir au résultat).
	if _state == State.RESULT and victorious:
		draw_line(base + Vector2(0, -30), base + Vector2(26 * face, -30), col, 6.0)
		draw_circle(base + Vector2(26 * face, -30), 4.0, Color(0.1, 0.1, 0.12))
	else:
		draw_line(base + Vector2(0, -28), base + Vector2(10 * face, -16), col, 6.0)


func _text(pos: Vector2, s: String, sz: int, c: Color, center := false) -> void:
	var font := ThemeDB.fallback_font
	var off := Vector2.ZERO
	if center:
		off.x = -font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x * 0.5
	draw_string(font, pos + off + Vector2(2, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.4))
	draw_string(font, pos + off, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)
