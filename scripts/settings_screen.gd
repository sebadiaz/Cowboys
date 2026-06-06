extends Control
## settings_screen.gd
## Écran de réglages léger, pensé mobile/web.
## Les valeurs sont persistées dans SaveManager pour survivre au refresh navigateur.

var _audio_btn: Button
var _volume_label: Label
var _touch_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.85, 0.74, 0.53)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 0)
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	box.add_child(_label("RÉGLAGES", 46, Color(0.35, 0.2, 0.1)))
	box.add_child(_label("Confort mobile / audio", 18, Color(0.4, 0.28, 0.16)))
	box.add_child(_spacer(14))

	_audio_btn = _button("", 54)
	_audio_btn.pressed.connect(_toggle_audio)
	box.add_child(_audio_btn)

	_volume_label = _label("", 18, Color(0.3, 0.2, 0.12))
	box.add_child(_volume_label)
	box.add_child(_row_button("Volume -", _volume_down, "Volume +", _volume_up))

	_touch_label = _label("", 18, Color(0.3, 0.2, 0.12))
	box.add_child(_touch_label)
	box.add_child(_row_button("Contrôles -", _touch_down, "Contrôles +", _touch_up))

	box.add_child(_label(
		"Astuce mobile : augmente les contrôles si le bouton TIR/E est trop petit sur ton téléphone.",
		15, Color(0.3, 0.2, 0.12)))

	box.add_child(_spacer(10))
	var back := _button("RETOUR", 52)
	back.pressed.connect(func() -> void: GameManager.goto_main_menu())
	box.add_child(back)

	_refresh()


func _toggle_audio() -> void:
	SaveManager.set_setting("audio_enabled", not SaveManager.audio_enabled())
	AudioManager.play("click", -8.0)
	_refresh()


func _volume_down() -> void:
	SaveManager.set_setting("sfx_volume", SaveManager.sfx_volume() - 0.1)
	AudioManager.play("click", -8.0)
	_refresh()


func _volume_up() -> void:
	SaveManager.set_setting("sfx_volume", SaveManager.sfx_volume() + 0.1)
	AudioManager.play("click", -8.0)
	_refresh()


func _touch_down() -> void:
	SaveManager.set_setting("touch_scale", SaveManager.touch_scale() - 0.1)
	AudioManager.play("click", -8.0)
	_refresh()


func _touch_up() -> void:
	SaveManager.set_setting("touch_scale", SaveManager.touch_scale() + 0.1)
	AudioManager.play("click", -8.0)
	_refresh()


func _refresh() -> void:
	if _audio_btn:
		_audio_btn.text = "Audio : %s" % ("ACTIVÉ" if SaveManager.audio_enabled() else "désactivé")
	if _volume_label:
		_volume_label.text = "Volume effets : %d %%" % int(round(SaveManager.sfx_volume() * 100.0))
	if _touch_label:
		_touch_label.text = "Taille contrôles tactiles : %d %%" % int(round(SaveManager.touch_scale() * 100.0))


func _row_button(left_text: String, left_action: Callable, right_text: String, right_action: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(500, 52)
	row.add_theme_constant_override("separation", 12)
	var left := _button(left_text, 52)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.pressed.connect(left_action)
	var right := _button(right_text, 52)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.pressed.connect(right_action)
	row.add_child(left)
	row.add_child(right)
	return row


func _button(text: String, h: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(500, h)
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
