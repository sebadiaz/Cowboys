extends CanvasLayer
## hud_controller.gd
## HUD de mission : objectif, butin, argent, jauge d'alarme, état discret/alerte.
## Gère aussi le menu pause (Échap). Construit son interface en code.

const MobileControlsScript := preload("res://scripts/mobile_controls.gd")

var _objective_label: Label
var _loot_label: Label
var _money_label: Label
var _state_label: Label
var _alarm_bar: ProgressBar
var _toast_label: Label
var _health_label: Label
var _ammo_label: Label
var _pause_root: Control
var _flash: ColorRect

var _money: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_build_flash()
	_build_pause_menu()
	_build_mobile_controls()


## Couche de flash plein écran (dégâts / alarme), au-dessus du jeu mais sous les
## libellés HUD. Couvre tout l'écran quelle que soit la résolution.
func _build_flash() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.z_index = -1
	add_child(_flash)
	move_child(_flash, 0)


## Déclenche un flash plein écran qui s'estompe.
func flash(color: Color) -> void:
	if not _flash:
		return
	_flash.color = color
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.45)


func _process(_delta: float) -> void:
	if InputManager.is_pause_just_pressed():
		_toggle_pause()


# --- Construction de l'UI ---

func _build_ui() -> void:
	var bar := ColorRect.new()
	bar.color = Color(0.1, 0.07, 0.05, 0.55)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 64
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	_objective_label = _make_label("Objectif: ...", 20)
	_objective_label.position = Vector2(16, 8)
	add_child(_objective_label)

	_loot_label = _make_label("Butin: 0 sac (0 $)", 16)
	_loot_label.position = Vector2(16, 36)
	add_child(_loot_label)

	_health_label = _make_label("PV: 3/3", 16)
	_health_label.position = Vector2(250, 36)
	add_child(_health_label)

	_ammo_label = _make_label("Balles: 6/6", 16)
	_ammo_label.position = Vector2(380, 36)
	add_child(_ammo_label)

	_money_label = _make_label("Argent: 0 $", 18)
	_money_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_money_label.position = Vector2(-220, 10)
	_money_label.size = Vector2(204, 24)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_money_label)

	_state_label = _make_label("DISCRET", 18)
	_state_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_state_label.position = Vector2(-70, 8)
	_state_label.size = Vector2(140, 24)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_state_label)

	_alarm_bar = ProgressBar.new()
	_alarm_bar.min_value = 0
	_alarm_bar.max_value = 100
	_alarm_bar.value = 0
	_alarm_bar.show_percentage = false
	_alarm_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_alarm_bar.position = Vector2(-110, 34)
	_alarm_bar.size = Vector2(220, 18)
	_alarm_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_alarm_bar)

	var alarm_caption := _make_label("Alarme", 12)
	alarm_caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	alarm_caption.position = Vector2(-110, 50)
	add_child(alarm_caption)

	_toast_label = _make_label("", 28)
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.position = Vector2(-300, 90)
	_toast_label.size = Vector2(600, 40)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0
	add_child(_toast_label)


func _make_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_pause_menu() -> void:
	_pause_root = Control.new()
	_pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.visible = false
	_pause_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # bloque les clics derrière le menu
	_pause_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(260, 0)
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := _make_label("PAUSE", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var resume := Button.new()
	resume.text = "Reprendre"
	resume.custom_minimum_size = Vector2(260, 48)
	resume.pressed.connect(_toggle_pause)
	box.add_child(resume)

	var menu := Button.new()
	menu.text = "Menu principal"
	menu.custom_minimum_size = Vector2(260, 48)
	menu.pressed.connect(_on_quit_to_menu)
	box.add_child(menu)


func _on_quit_to_menu() -> void:
	GameManager.goto_main_menu()


func _build_mobile_controls() -> void:
	var mc := Control.new()
	mc.set_script(MobileControlsScript)
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mc)


# --- API appelée par mission_manager ---

func set_objective(text: String) -> void:
	if _objective_label:
		_objective_label.text = "Objectif: " + text


func set_loot(bags: int, value: int) -> void:
	if _loot_label:
		var word := "sac" if bags <= 1 else "sacs"
		_loot_label.text = "Butin: %d %s (%d $)" % [bags, word, value]


func set_money(amount: int) -> void:
	_money = amount
	if _money_label:
		_money_label.text = "Argent: %d $" % amount


func set_alarm(value: float) -> void:
	if _alarm_bar:
		_alarm_bar.value = value
		var t := clampf(value / 100.0, 0.0, 1.0)
		_alarm_bar.modulate = Color(1.0, 1.0 - t, 0.2)


func set_state(alert: bool) -> void:
	if not _state_label:
		return
	if alert:
		_state_label.text = "ALERTE"
		_state_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	else:
		_state_label.text = "DISCRET"
		_state_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))


func set_health(current_hp: int, max_hp: int) -> void:
	if not _health_label:
		return
	_health_label.text = "PV: %d/%d" % [current_hp, max_hp]
	_health_label.add_theme_color_override("font_color",
		Color(1.0, 0.4, 0.4) if current_hp <= 1 else Color(1, 1, 1))


func set_ammo(in_cylinder: int, capacity: int, reloading: bool) -> void:
	if not _ammo_label:
		return
	if reloading:
		_ammo_label.text = "Rechargement…"
		_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	else:
		_ammo_label.text = "Balles: %d/%d" % [in_cylinder, capacity]
		_ammo_label.add_theme_color_override("font_color",
			Color(1.0, 0.5, 0.4) if in_cylinder == 0 else Color(1, 1, 1))


func show_toast(text: String) -> void:
	if not _toast_label:
		return
	_toast_label.text = text
	_toast_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(_toast_label, "modulate:a", 0.0, 0.8)


# --- Pause ---

func _toggle_pause() -> void:
	var tree := get_tree()
	tree.paused = not tree.paused
	if _pause_root:
		_pause_root.visible = tree.paused
