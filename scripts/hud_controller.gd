extends CanvasLayer
## hud_controller.gd
## HUD de mission : objectif, butin, argent, jauge d'alarme, état discret/alerte.
## Gère aussi le menu pause (Échap). Construit son interface en code.

const MobileControlsScript := preload("res://scripts/mobile_controls.gd")
const HudGfxScript := preload("res://scripts/hud_gfx.gd")

var _gfx: Control
var _toast_label: Label
var _pause_root: Control
var _flash: ColorRect
var _alert_overlay: ColorRect

var _money: int = 0
var _alarm_ratio: float = 0.0
var _global_alert: bool = false
var _pulse_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_build_flash()
	_build_pause_menu()
	_build_mobile_controls()


## Couche de flash plein écran (dégâts / alarme), au-dessus du jeu mais sous les
## libellés HUD. Couvre tout l'écran quelle que soit la résolution.
func _build_flash() -> void:
	# Teinte rouge d'ambiance qui pulse quand l'alarme monte (sous le flash).
	_alert_overlay = ColorRect.new()
	_alert_overlay.color = Color(0.8, 0.05, 0.05, 0.0)
	_alert_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_alert_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_overlay.z_index = -2
	add_child(_alert_overlay)
	move_child(_alert_overlay, 0)

	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.z_index = -1
	add_child(_flash)
	move_child(_flash, 1)


## Déclenche un flash plein écran qui s'estompe.
func flash(color: Color) -> void:
	if not _flash:
		return
	_flash.color = color
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.45)


func _process(delta: float) -> void:
	if InputManager.is_pause_just_pressed():
		_toggle_pause()
	# Pulsation rouge : plus l'alarme est haute, plus ça bat fort et vite.
	if _alert_overlay != null:
		var base := _alarm_ratio * 0.10
		var amp := 0.04 + _alarm_ratio * 0.12
		var speed := 3.0 + _alarm_ratio * 6.0
		if _global_alert:
			base = 0.12
			amp = 0.12
			speed = 9.0
		_pulse_t += delta * speed
		var a: float = base + amp * (0.5 + 0.5 * sin(_pulse_t))
		_alert_overlay.color.a = clampf(a, 0.0, 0.32) if (_alarm_ratio > 0.02 or _global_alert) else 0.0


# --- Construction de l'UI ---

func _build_ui() -> void:
	# Couche de dessin "premium" (cuir/laiton/or), peinte dans hud_gfx.
	_gfx = Control.new()
	_gfx.set_script(HudGfxScript)
	_gfx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gfx)

	# Bandeau dramatique (toasts) centré, au-dessus du HUD.
	_toast_label = _make_label("", 28)
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.position = Vector2(-300, 88)
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
	if _gfx:
		_gfx.objective = text


func set_loot(bags: int, value: int) -> void:
	if _gfx:
		_gfx.loot_bags = bags
		_gfx.loot_value = value


func set_money(amount: int) -> void:
	_money = amount
	if _gfx:
		_gfx.money = amount


func set_alarm(value: float) -> void:
	_alarm_ratio = clampf(value / 100.0, 0.0, 1.0)
	if value >= 100.0:
		_global_alert = true
	if _gfx:
		_gfx.alarm = _alarm_ratio
		_gfx.global_alert = _global_alert


func set_state(alert: bool) -> void:
	if _gfx:
		_gfx.state_alert = alert


func set_health(current_hp: int, max_hp: int) -> void:
	if _gfx:
		_gfx.hp = current_hp
		_gfx.max_hp = max_hp


func set_ammo(in_cylinder: int, capacity: int, reloading: bool) -> void:
	if _gfx:
		_gfx.ammo = in_cylinder
		_gfx.cap = capacity
		_gfx.reloading = reloading


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
