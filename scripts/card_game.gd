extends Control
class_name CardGame
## card_game.gd — « VINGT-ET-UN » (Blackjack) au saloon.
## Activité de jeu autonome : on s'assoit à la table, on MISE son butin contre le
## croupier, on TIRE / RESTE, le croupier joue à 17, on encaisse ou on perd.
## Overlay screen-space (posé sous une CanvasLayer par le saloon), entrées propres
## (boutons tactiles + clavier), argent résolu via SaveManager, puis se ferme.
## Tout est dessiné (aucun asset) — règle CC0 respectée.

signal closed

enum State { BETTING, PLAYER, DEALER, RESULT }

const MIN_BET := 10
const SUITS := ["♠", "♥", "♦", "♣"]
const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

var _state: int = State.BETTING
var bet := 50
var _deck: Array[int] = []
var _player: Array[int] = []
var _dealer: Array[int] = []
var _reveal := false                # le croupier montre sa carte cachée
var _result := ""
var _result_col := Color.WHITE
var _last_delta := 0                 # gain/perte du dernier coup (affichage)
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _deal_anim := 0.0

var _btns: Dictionary = {}           # nom -> Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	_build_buttons()
	_refresh_buttons()
	set_process(true)


func _build_buttons() -> void:
	for spec in [
			["bet_dn", "− 10"], ["bet_up", "+ 10"], ["deal", "DISTRIBUER"],
			["hit", "TIRER"], ["stand", "RESTER"], ["again", "REJOUER"], ["quit", "QUITTER"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_on_button.bind(spec[0]))
		add_child(b)
		_btns[spec[0]] = b


func _layout_buttons() -> void:
	var vp := size if size.x > 1.0 else get_viewport_rect().size
	var cy := vp.y - 86.0
	var w := 200.0
	var h := 60.0
	# Range centrée selon l'état.
	var row: Array = []
	match _state:
		State.BETTING: row = ["bet_dn", "bet_up", "deal", "quit"]
		State.PLAYER: row = ["hit", "stand"]
		State.RESULT: row = ["again", "quit"]
		_: row = []
	var total := row.size() * w + maxf(0.0, row.size() - 1) * 16.0
	var x := vp.x * 0.5 - total * 0.5
	for name in _btns:
		_btns[name].visible = name in row
	for name in row:
		var b: Button = _btns[name]
		b.size = Vector2(w, h)
		b.position = Vector2(x, cy)
		x += w + 16.0


func _refresh_buttons() -> void:
	_layout_buttons()
	if _btns.has("deal"):
		_btns["deal"].disabled = SaveManager.total_money < bet
		_btns["deal"].text = "DISTRIBUER  (mise %d $)" % bet


func _on_button(which: String) -> void:
	match which:
		"bet_dn": _change_bet(-10)
		"bet_up": _change_bet(10)
		"deal": _deal()
		"hit": _player_hit()
		"stand": _player_stand()
		"again": _reset_round()
		"quit": _close()


func _change_bet(d: int) -> void:
	if _state != State.BETTING:
		return
	var cap: int = maxi(MIN_BET, SaveManager.total_money)
	bet = clampi(bet + d, MIN_BET, cap)
	AudioManager.play("click")
	_refresh_buttons()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match _state:
			State.BETTING:
				if event.keycode == KEY_UP or event.keycode == KEY_RIGHT: _change_bet(10)
				elif event.keycode == KEY_DOWN or event.keycode == KEY_LEFT: _change_bet(-10)
				elif event.keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]: _deal()
				elif event.keycode == KEY_ESCAPE: _close()
			State.PLAYER:
				if event.keycode == KEY_H: _player_hit()
				elif event.keycode in [KEY_S, KEY_SPACE]: _player_stand()
			State.RESULT:
				if event.keycode in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]: _reset_round()
				elif event.keycode == KEY_ESCAPE: _close()
		get_viewport().set_input_as_handled()


# --- Logique de jeu ---

func _fresh_deck() -> void:
	_deck.clear()
	for i in range(52):
		_deck.append(i)
	# Mélange Fisher-Yates.
	for i in range(_deck.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _deck[i]
		_deck[i] = _deck[j]
		_deck[j] = tmp


func _draw_card() -> int:
	if _deck.is_empty():
		_fresh_deck()
	return _deck.pop_back()


## Valeur d'une main (As = 11 réduit à 1 tant que > 21).
func hand_value(cards: Array) -> int:
	var total := 0
	var aces := 0
	for c in cards:
		var rank: int = int(c) % 13
		if rank == 0:
			aces += 1
			total += 11
		else:
			total += mini(10, rank + 1)
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total


func _deal() -> void:
	if _state != State.BETTING:
		return
	bet = clampi(bet, MIN_BET, maxi(MIN_BET, SaveManager.total_money))
	if not SaveManager.spend(bet):
		_flash_result("PAS ASSEZ DE BUTIN !", Color(1, 0.5, 0.4))
		return
	_fresh_deck()
	_player = [_draw_card(), _draw_card()]
	_dealer = [_draw_card(), _draw_card()]
	_reveal = false
	_result = ""
	_deal_anim = 0.0
	AudioManager.play("click")
	# Blackjack naturel ?
	if hand_value(_player) == 21:
		_player_stand()
	else:
		_state = State.PLAYER
	_refresh_buttons()


func _player_hit() -> void:
	if _state != State.PLAYER:
		return
	_player.append(_draw_card())
	AudioManager.play("click")
	if hand_value(_player) > 21:
		_resolve()    # bust
	_refresh_buttons()


func _player_stand() -> void:
	if _state != State.PLAYER and _state != State.BETTING:
		return
	_state = State.DEALER
	_reveal = true
	# Le croupier tire jusqu'à 17.
	while hand_value(_dealer) < 17:
		_dealer.append(_draw_card())
	_resolve()


func _resolve() -> void:
	_reveal = true
	var pv := hand_value(_player)
	var dv := hand_value(_dealer)
	var pay := 0
	var natural := _player.size() == 2 and pv == 21
	if pv > 21:
		_result = "PERDU — tu sautes !"
		_result_col = Color(1, 0.45, 0.35)
	elif natural and not (_dealer.size() == 2 and dv == 21):
		_result = "VINGT-ET-UN ! (×1.5)"
		_result_col = Color(1, 0.9, 0.4)
		pay = int(bet * 2.5)
	elif dv > 21 or pv > dv:
		_result = "GAGNÉ !"
		_result_col = Color(0.6, 1.0, 0.6)
		pay = bet * 2
	elif pv == dv:
		_result = "ÉGALITÉ — mise rendue"
		_result_col = Color(0.9, 0.9, 0.7)
		pay = bet
	else:
		_result = "PERDU — le croupier gagne"
		_result_col = Color(1, 0.45, 0.35)
	if pay > 0:
		SaveManager.refund(pay)
	_last_delta = pay - bet
	AudioManager.play("win" if _last_delta > 0 else ("click" if _last_delta == 0 else "lose"), 0.0)
	_state = State.RESULT
	_refresh_buttons()


func _flash_result(msg: String, col: Color) -> void:
	_result = msg
	_result_col = col


func _reset_round() -> void:
	_player.clear()
	_dealer.clear()
	_reveal = false
	_result = ""
	_state = State.BETTING
	_refresh_buttons()


func _close() -> void:
	closed.emit()
	queue_free()


# --- Rendu ---

func _process(delta: float) -> void:
	_t += delta
	_deal_anim = minf(1.0, _deal_anim + delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var vp := size if size.x > 1.0 else get_viewport_rect().size
	# Voile + feutrine de table.
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.03, 0.05, 0.72))
	var table := Rect2(vp.x * 0.5 - 430, vp.y * 0.22, 860, vp.y * 0.5)
	table = table.intersection(Rect2(Vector2.ZERO, vp))
	draw_rect(Rect2(vp * 0.5 - Vector2(440, 30), Vector2(880, 8)), Color(0.25, 0.16, 0.08))
	_round_rect(Rect2(vp.x * 0.5 - 430, vp.y * 0.20, 860, 320), Color(0.10, 0.34, 0.20), 26.0)
	_round_rect(Rect2(vp.x * 0.5 - 414, vp.y * 0.20 + 14, 828, 292), Color(0.13, 0.42, 0.25), 20.0)

	var cx := vp.x * 0.5
	# Titre + magot.
	_text(Vector2(cx, vp.y * 0.10), "♠ VINGT-ET-UN ♥", 34, Color(0.96, 0.88, 0.55), true)
	_text(Vector2(cx, vp.y * 0.10 + 30), "Butin : %d $" % SaveManager.total_money, 18, Color(1, 0.9, 0.6), true)

	# Mains.
	var dy := vp.y * 0.24
	var py := vp.y * 0.50
	_text(Vector2(cx - 360, dy - 14), "CROUPIER", 16, Color(0.9, 0.85, 0.8))
	_draw_hand(_dealer, Vector2(cx - 230, dy), not _reveal)
	if _reveal or _state == State.RESULT:
		_text(Vector2(cx + 250, dy + 30), "= %d" % hand_value(_dealer), 22, Color(1, 1, 0.85))
	_text(Vector2(cx - 360, py - 14), "TOI", 16, Color(0.9, 0.95, 0.85))
	_draw_hand(_player, Vector2(cx - 230, py), false)
	if not _player.is_empty():
		var pv := hand_value(_player)
		var pc := Color(1, 0.5, 0.4) if pv > 21 else Color(1, 1, 0.85)
		_text(Vector2(cx + 250, py + 30), "= %d" % pv, 24, pc)

	# Bandeaux d'état / consignes.
	match _state:
		State.BETTING:
			_text(Vector2(cx, vp.y * 0.18), "Règle ta MISE puis DISTRIBUE — bats le croupier sans dépasser 21", 17, Color(1, 0.92, 0.7), true)
			_text(Vector2(cx, py + 90), "MISE : %d $" % bet, 30, Color(1, 0.9, 0.45), true)
		State.PLAYER:
			_text(Vector2(cx, py + 90), "TIRER une carte ou RESTER ?", 22, Color(0.95, 1, 0.8), true)
		State.RESULT:
			_text(Vector2(cx, py + 86), _result, 30, _result_col, true)
			var ds := ("+%d $" % _last_delta) if _last_delta > 0 else ("%d $" % _last_delta if _last_delta < 0 else "± 0 $")
			_text(Vector2(cx, py + 118), ds, 22, _result_col, true)


func _draw_hand(cards: Array, origin: Vector2, hide_second: bool) -> void:
	for i in range(cards.size()):
		var pos := origin + Vector2(i * 64.0, 0)
		if i == 1 and hide_second:
			_draw_card_back(pos)
		else:
			_draw_card_face(int(cards[i]), pos)


func _draw_card_face(card: int, pos: Vector2) -> void:
	var rank: int = card % 13
	var suit: int = card / 13
	var red := suit == 1 or suit == 2
	var col := Color(0.85, 0.15, 0.12) if red else Color(0.10, 0.10, 0.12)
	var r := Rect2(pos, Vector2(56, 80))
	_round_rect(Rect2(pos + Vector2(2, 3), Vector2(56, 80)), Color(0, 0, 0, 0.3), 7.0)
	_round_rect(r, Color(0.97, 0.96, 0.92), 7.0)
	_text(pos + Vector2(14, 6), RANKS[rank], 20, col)
	_text(pos + Vector2(28, 34), SUITS[suit], 30, col, true)


func _draw_card_back(pos: Vector2) -> void:
	_round_rect(Rect2(pos + Vector2(2, 3), Vector2(56, 80)), Color(0, 0, 0, 0.3), 7.0)
	_round_rect(Rect2(pos, Vector2(56, 80)), Color(0.45, 0.16, 0.16), 7.0)
	_round_rect(Rect2(pos + Vector2(6, 6), Vector2(44, 68)), Color(0.7, 0.55, 0.3), 5.0)
	_round_rect(Rect2(pos + Vector2(11, 11), Vector2(34, 58)), Color(0.45, 0.16, 0.16), 4.0)


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
