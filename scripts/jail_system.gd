extends Control
## jail_system.gd  (Lot 15)
## PRISON : on y atterrit après un braquage de banque raté (pris par la loi).
## Deux sorties : payer la CAUTION (si on a le magot) ou CROCHETER la serrure
## (mini-jeu d'adresse : stopper l'aiguille dans la zone verte 3 fois). Se faire
## repérer par le gardien remet le crochetage à zéro. S'évader augmente la prime.

var _t := 0.0
var _needle := 0.0          # 0..1 position de l'aiguille
var _speed := 0.9           # vitesse de l'aiguille (monte à chaque crochet)
var _green0 := 0.40         # bornes de la zone verte (rétrécit à chaque crochet)
var _green1 := 0.60
var _picks := 0             # crochets réussis (3 = évadé)
var _vigil := 0             # vigilance du gardien (3 = repéré)
var _flash := ""
var _flash_t := 0.0
var _done := false

var _bail := 0
var _info: Label
var _bail_btn: Button
var _msg: Label
var _bar_green: ColorRect
var _bar_needle: ColorRect
var _vig: Array[ColorRect] = []
const BAR_X := 30.0
const BAR_W := 460.0
const BAR_Y := 58.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	UiTheme.add_backdrop(self, "lose")
	_bail = 250 + SaveManager.notoriety * 130

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiTheme.panel()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	box.add_child(UiTheme.title("⛓ EN PRISON", 40, Color(0.95, 0.7, 0.3)))
	box.add_child(_lbl("Le shérif t'a coffré. Paie ta caution… ou crochète la serrure.", 17,
			Color(0.9, 0.85, 0.7)))
	_info = _lbl("", 18, Color(0.95, 0.88, 0.6))
	box.add_child(_info)

	# Mini-jeu de crochetage : nœuds enfants (au-dessus du panneau, donc visibles).
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(520, 130)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(slot)
	slot.add_child(_rect(Vector2(BAR_X - 3, BAR_Y - 3), Vector2(BAR_W + 6, 26), Color(0.10, 0.07, 0.05)))
	slot.add_child(_rect(Vector2(BAR_X, BAR_Y), Vector2(BAR_W, 20), Color(0.30, 0.22, 0.15)))
	_bar_green = _rect(Vector2(BAR_X, BAR_Y), Vector2(BAR_W * 0.2, 20), Color(0.35, 0.8, 0.35, 0.9))
	slot.add_child(_bar_green)
	_bar_needle = _rect(Vector2(BAR_X, BAR_Y - 8), Vector2(5, 36), Color(0.98, 0.92, 0.5))
	slot.add_child(_bar_needle)
	slot.add_child(_lbl_left("Vigilance :", Vector2(BAR_X, BAR_Y + 36)))
	for v in range(3):
		var d := _rect(Vector2(BAR_X + 100 + v * 22, BAR_Y + 40), Vector2(13, 13), Color(0.4, 0.35, 0.3))
		slot.add_child(d)
		_vig.append(d)

	_msg = _lbl("", 16, Color(1, 0.85, 0.4))
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_msg)

	var pick := Button.new()
	pick.text = "🔓 CROCHETER (Espace / clic)"
	pick.custom_minimum_size = Vector2(520, 54)
	pick.pressed.connect(_attempt_pick)
	box.add_child(pick)

	_bail_btn = Button.new()
	_bail_btn.custom_minimum_size = Vector2(520, 50)
	_bail_btn.pressed.connect(_pay_bail)
	box.add_child(_bail_btn)

	var give := Button.new()
	give.text = "Croupir en cellule (retour au menu)"
	give.custom_minimum_size = Vector2(520, 40)
	give.modulate = Color(1, 1, 1, 0.7)
	give.pressed.connect(func() -> void: GameManager.goto_main_menu())
	box.add_child(give)

	_refresh()
	AudioManager.play_music("tension")


func _refresh() -> void:
	_info.text = "Magot : %d $    ·    Caution : %d $    ·    Crochets : %d/3" % [
			SaveManager.total_money, _bail, _picks]
	var ok := SaveManager.total_money >= _bail
	_bail_btn.text = "💰 Payer la caution (%d $)" % _bail if ok else "Caution trop chère (%d $)" % _bail
	_bail_btn.disabled = not ok


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	# Aiguille en va-et-vient (onde triangulaire), accélère avec les crochets.
	_needle = absf(fmod(_t * _speed, 2.0) - 1.0)
	if _bar_needle != null:
		_bar_needle.position.x = BAR_X + BAR_W * _needle - 2.5
		_bar_green.position.x = BAR_X + BAR_W * _green0
		_bar_green.size.x = BAR_W * (_green1 - _green0)
		for v in range(3):
			_vig[v].color = Color(0.9, 0.3, 0.25) if v < _vigil else Color(0.4, 0.35, 0.3)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash = ""
			_msg.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE) \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		_attempt_pick()


func _attempt_pick() -> void:
	if _done:
		return
	if _needle >= _green0 and _needle <= _green1:
		_picks += 1
		_speed += 0.5
		# La zone verte rétrécit et se déplace.
		var w := maxf(0.10, (_green1 - _green0) * 0.78)
		var c := clampf(randf_range(0.25, 0.75), w * 0.5, 1.0 - w * 0.5)
		_green0 = c - w * 0.5
		_green1 = c + w * 0.5
		AudioManager.play("pickup")
		_set_msg("*clic* — %d/3" % _picks, Color(0.6, 1.0, 0.6))
		if _picks >= 3:
			_escape()
	else:
		_vigil += 1
		AudioManager.play("click")
		if _vigil >= 3:
			_vigil = 0
			_picks = 0
			_speed = 0.9
			_green0 = 0.40
			_green1 = 0.60
			SaveManager.spend(mini(80, SaveManager.total_money))   # le gardien te confisque un peu
			_set_msg("Le gardien te repère ! Crochets perdus.", Color(1, 0.4, 0.3))
		else:
			_set_msg("Raté… vigilance %d/3" % _vigil, Color(1, 0.7, 0.3))
	_refresh()


func _set_msg(s: String, _c: Color) -> void:
	_msg.text = s
	_flash = s
	_flash_t = 1.4


func _escape() -> void:
	_done = true
	SaveManager.gain_notoriety()   # s'évader te rend plus recherché
	_msg.text = "ÉVASION ! Tu files dans la nuit."
	AudioManager.play("win", 2.0)
	AudioManager.stop_music()
	_leave()


func _pay_bail() -> void:
	if _done or not SaveManager.spend(_bail):
		return
	_done = true
	_msg.text = "Caution payée. Libre… pour l'instant."
	AudioManager.play("safe")
	AudioManager.stop_music()
	_leave()


func _leave() -> void:
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(func() -> void: GameManager.goto_world_map())


func _draw() -> void:
	# Barreaux de cellule en avant-plan (ambiance) — derrière le panneau.
	for i in range(int(size.x / 70.0) + 1):
		draw_rect(Rect2(i * 70.0 + 12.0, 0, 8, size.y), Color(0.10, 0.10, 0.12, 0.16))


func _rect(pos: Vector2, sz: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _lbl_left(text: String, pos: Vector2) -> Label:
	var l := _lbl(text, 14, Color(0.85, 0.8, 0.65))
	l.position = pos
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _lbl(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
