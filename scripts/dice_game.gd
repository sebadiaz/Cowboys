extends Control
class_name DiceGame
## dice_game.gd — CHUCK-A-LUCK (jeu de dés du saloon, « cage à oiseaux »).
## On parie sur un chiffre (1–6) et sa MISE ; trois dés roulent. Le chiffre sort
## sur 1, 2 ou 3 dés → on est payé 1×, 2× ou 3× la mise (mise rendue en plus) ;
## absent → mise perdue. Overlay autonome screen-space (posé par le saloon),
## entrées propres (boutons tactiles + clavier), tout dessiné — aucun asset.

signal closed

enum State { BETTING, ROLLING, RESULT }

const MIN_BET := 10

var _state: int = State.BETTING
var bet := 50
var pick := 3                        # chiffre parié (1–6)
var _dice: Array[int] = [1, 1, 1]
var _roll_t := 0.0
var _matches := 0
var _last_delta := 0
var _result := ""
var _result_col := Color.WHITE
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _btns: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	_build_buttons()
	_refresh()


func _build_buttons() -> void:
	for spec in [["pick_dn", "◀ chiffre"], ["pick_up", "chiffre ▶"],
			["bet_dn", "− 10"], ["bet_up", "+ 10"], ["roll", "LANCER"],
			["again", "REJOUER"], ["quit", "QUITTER"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_on_button.bind(spec[0]))
		add_child(b)
		_btns[spec[0]] = b


func _layout_buttons() -> void:
	var vp := size if size.x > 1.0 else get_viewport_rect().size
	var row: Array = []
	match _state:
		State.BETTING: row = ["pick_dn", "pick_up", "bet_dn", "bet_up", "roll", "quit"]
		State.RESULT: row = ["again", "quit"]
	var w := 150.0
	var h := 58.0
	var total := row.size() * w + maxf(0.0, row.size() - 1) * 12.0
	var x := vp.x * 0.5 - total * 0.5
	for n in _btns:
		_btns[n].visible = n in row
	for n in row:
		var b: Button = _btns[n]
		b.size = Vector2(w, h)
		b.position = Vector2(x, vp.y - 88.0)
		x += w + 12.0


func _refresh() -> void:
	_layout_buttons()
	if _btns.has("roll"):
		_btns["roll"].disabled = SaveManager.total_money < bet
		_btns["roll"].text = "LANCER (%d $)" % bet


func _on_button(which: String) -> void:
	match which:
		"pick_dn": _change_pick(-1)
		"pick_up": _change_pick(1)
		"bet_dn": _change_bet(-10)
		"bet_up": _change_bet(10)
		"roll": _roll()
		"again": _reset()
		"quit": _close()


func _change_pick(d: int) -> void:
	if _state != State.BETTING:
		return
	pick = wrapi(pick - 1 + d, 0, 6) + 1
	AudioManager.play("click")
	queue_redraw()


func _change_bet(d: int) -> void:
	if _state != State.BETTING:
		return
	bet = clampi(bet + d, MIN_BET, maxi(MIN_BET, SaveManager.total_money))
	AudioManager.play("click")
	_refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match _state:
			State.BETTING:
				if event.keycode in [KEY_LEFT, KEY_DOWN]: _change_pick(-1)
				elif event.keycode in [KEY_RIGHT, KEY_UP]: _change_pick(1)
				elif event.keycode == KEY_A: _change_bet(-10)
				elif event.keycode == KEY_E: _change_bet(10)
				elif event.keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]: _roll()
				elif event.keycode == KEY_ESCAPE: _close()
			State.RESULT:
				if event.keycode in [KEY_ENTER, KEY_SPACE]: _reset()
				elif event.keycode == KEY_ESCAPE: _close()
		get_viewport().set_input_as_handled()


# --- Logique ---

func _roll() -> void:
	if _state != State.BETTING:
		return
	bet = clampi(bet, MIN_BET, maxi(MIN_BET, SaveManager.total_money))
	if not SaveManager.spend(bet):
		_result = "PAS ASSEZ DE BUTIN !"
		_result_col = Color(1, 0.5, 0.4)
		return
	# Les dés sont décidés maintenant ; l'animation ne fait que les faire tourner.
	_dice = [_rng.randi_range(1, 6), _rng.randi_range(1, 6), _rng.randi_range(1, 6)]
	_state = State.ROLLING
	_roll_t = 0.7
	AudioManager.play("click")
	_refresh()


func _settle() -> void:
	_matches = 0
	for d in _dice:
		if d == pick:
			_matches += 1
	var pay := 0
	if _matches > 0:
		pay = bet * (1 + _matches)          # mise rendue + 1× par dé gagnant
		_result = "%d × ton chiffre !  (×%d)" % [_matches, _matches]
		_result_col = Color(0.6, 1.0, 0.6) if _matches >= 1 else Color.WHITE
		SaveManager.refund(pay)
		AudioManager.play("win", -2.0)
	else:
		_result = "Perdu — ton %d n'est pas sorti" % pick
		_result_col = Color(1, 0.45, 0.35)
		AudioManager.play("lose", -2.0)
	_last_delta = pay - bet
	_state = State.RESULT
	_refresh()


func _reset() -> void:
	_state = State.BETTING
	_result = ""
	_refresh()


func _close() -> void:
	closed.emit()
	queue_free()


# --- Rendu ---

func _process(delta: float) -> void:
	_t += delta
	if _state == State.ROLLING:
		_roll_t -= delta
		if _roll_t <= 0.0:
			_settle()
	queue_redraw()


func _draw() -> void:
	var vp := size if size.x > 1.0 else get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.03, 0.05, 0.72))
	_round_rect(Rect2(vp.x * 0.5 - 380, vp.y * 0.20, 760, 320), Color(0.12, 0.30, 0.40), 24.0)
	_round_rect(Rect2(vp.x * 0.5 - 364, vp.y * 0.20 + 14, 728, 292), Color(0.16, 0.38, 0.48), 18.0)
	var cx := vp.x * 0.5

	_text(Vector2(cx, vp.y * 0.10), "⚂ CHUCK-A-LUCK ⚄", 32, Color(0.96, 0.88, 0.55), true)
	_text(Vector2(cx, vp.y * 0.10 + 28), "Butin : %d $" % SaveManager.total_money, 18, Color(1, 0.9, 0.6), true)

	# Les trois dés.
	var dy := vp.y * 0.34
	for i in range(3):
		var face: int = _dice[i]
		if _state == State.ROLLING:
			face = _rng.randi_range(1, 6)       # défilement
		_draw_die(Vector2(cx - 130 + i * 110.0, dy), face, _state == State.RESULT and face == pick)

	# Ton chiffre parié.
	_text(Vector2(cx, dy + 120), "TON CHIFFRE :", 18, Color(0.9, 0.95, 1.0), true)
	_draw_die(Vector2(cx - 28, dy + 132), pick, true)

	match _state:
		State.BETTING:
			_text(Vector2(cx, vp.y * 0.18), "Choisis un chiffre, mise, puis LANCE les 3 dés", 17, Color(1, 0.92, 0.7), true)
			_text(Vector2(cx, dy + 232), "MISE : %d $" % bet, 26, Color(1, 0.9, 0.45), true)
		State.ROLLING:
			_text(Vector2(cx, dy + 232), "…ça roule…", 24, Color(1, 0.95, 0.7), true)
		State.RESULT:
			_text(Vector2(cx, dy + 226), _result, 26, _result_col, true)
			var ds := ("+%d $" % _last_delta) if _last_delta > 0 else ("%d $" % _last_delta if _last_delta < 0 else "± 0 $")
			_text(Vector2(cx, dy + 256), ds, 22, _result_col, true)


func _draw_die(pos: Vector2, value: int, glow := false) -> void:
	var r := Rect2(pos, Vector2(56, 56))
	if glow:
		_round_rect(Rect2(pos - Vector2(3, 3), Vector2(62, 62)), Color(1, 0.9, 0.4, 0.8), 10.0)
	_round_rect(Rect2(pos + Vector2(2, 3), Vector2(56, 56)), Color(0, 0, 0, 0.3), 8.0)
	_round_rect(r, Color(0.97, 0.96, 0.92), 8.0)
	var c := pos + Vector2(28, 28)
	var o := 15.0
	var dot := Color(0.12, 0.10, 0.12)
	var pips := {
		1: [Vector2(0, 0)],
		2: [Vector2(-o, -o), Vector2(o, o)],
		3: [Vector2(-o, -o), Vector2(0, 0), Vector2(o, o)],
		4: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, o), Vector2(o, o)],
		5: [Vector2(-o, -o), Vector2(o, -o), Vector2(0, 0), Vector2(-o, o), Vector2(o, o)],
		6: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, 0), Vector2(o, 0), Vector2(-o, o), Vector2(o, o)],
	}
	for p in pips.get(value, []):
		draw_circle(c + p, 5.0, dot)


func _round_rect(r: Rect2, col: Color, rad: float) -> void:
	draw_rect(Rect2(r.position + Vector2(rad, 0), r.size - Vector2(rad * 2, 0)), col)
	draw_rect(Rect2(r.position + Vector2(0, rad), r.size - Vector2(0, rad * 2)), col)
	for c in [r.position + Vector2(rad, rad), r.position + Vector2(r.size.x - rad, rad),
			r.position + Vector2(rad, r.size.y - rad), r.position + Vector2(r.size.x - rad, r.size.y - rad)]:
		draw_circle(c, rad, col)


func _text(pos: Vector2, s: String, sz: int, col: Color, center := false) -> void:
	var font := ThemeDB.fallback_font
	var off := Vector2.ZERO
	if center:
		off.x = -font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x * 0.5
	draw_string(font, pos + off + Vector2(1.5, 1.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.6))
	draw_string(font, pos + off, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
