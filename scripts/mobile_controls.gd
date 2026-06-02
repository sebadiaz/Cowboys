extends Control
## mobile_controls.gd
## Contrôles tactiles pour navigateur mobile : un joystick virtuel (moitié
## gauche de l'écran) et un bouton d'interaction (bas-droite). Les valeurs sont
## poussées dans InputManager, fusionnées avec le clavier. Fonctionne aussi à la
## souris (émulation tactile) pour tester sur desktop.

const JOY_RADIUS := 95.0
const DEADZONE := 0.14
const KNOB_RADIUS := 38.0

## Boutons de combat (TIR / RECH / E). Désactivés en ville (déplacement seul).
@export var combat_buttons := true

var _active := false
var _touch_index := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO

var _interact_btn: Button
var _fire_btn: Button
var _reload_btn: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not combat_buttons:
		return  # en ville : joystick seul (pas de tir/recharge/interaction)
	_interact_btn = Button.new()
	_interact_btn.text = "E"
	_interact_btn.add_theme_font_size_override("font_size", 28)
	_interact_btn.custom_minimum_size = Vector2(120, 120)
	_interact_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_interact_btn.position = Vector2(-150, -150)
	_interact_btn.modulate = Color(1, 1, 1, 0.85)
	_interact_btn.button_down.connect(func() -> void: InputManager.set_touch_interact_held(true))
	_interact_btn.button_up.connect(func() -> void: InputManager.set_touch_interact_held(false))
	add_child(_interact_btn)

	_fire_btn = Button.new()
	_fire_btn.text = "TIR"
	_fire_btn.add_theme_font_size_override("font_size", 26)
	_fire_btn.custom_minimum_size = Vector2(130, 130)
	_fire_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fire_btn.position = Vector2(-160, -300)
	_fire_btn.modulate = Color(1, 0.85, 0.8, 0.9)
	_fire_btn.button_down.connect(func() -> void: InputManager.set_touch_fire_held(true))
	_fire_btn.button_up.connect(func() -> void: InputManager.set_touch_fire_held(false))
	add_child(_fire_btn)

	_reload_btn = Button.new()
	_reload_btn.text = "RECH"
	_reload_btn.add_theme_font_size_override("font_size", 20)
	_reload_btn.custom_minimum_size = Vector2(96, 70)
	_reload_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_reload_btn.position = Vector2(-160, -380)
	_reload_btn.modulate = Color(1, 0.95, 0.7, 0.9)
	_reload_btn.pressed.connect(func() -> void: InputManager.trigger_touch_reload())
	add_child(_reload_btn)


func _in_joystick_zone(pos: Vector2) -> bool:
	# Moitié gauche de l'écran (le bouton interaction occupe le bas-droite).
	return pos.x < size.x * 0.5


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _active and _in_joystick_zone(event.position):
				_active = true
				_touch_index = event.index
				_base = event.position
				_knob = event.position
				queue_redraw()
		elif event.index == _touch_index:
			_reset_joystick()
	elif event is InputEventScreenDrag and _active and event.index == _touch_index:
		var offset: Vector2 = event.position - _base
		if offset.length() > JOY_RADIUS:
			offset = offset.normalized() * JOY_RADIUS
		_knob = _base + offset
		var v: Vector2 = offset / JOY_RADIUS
		if v.length() < DEADZONE:
			v = Vector2.ZERO
		InputManager.set_touch_move(v)
		queue_redraw()


func _reset_joystick() -> void:
	_active = false
	_touch_index = -1
	InputManager.set_touch_move(Vector2.ZERO)
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	draw_circle(_base, JOY_RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(_base, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
	draw_circle(_knob, KNOB_RADIUS, Color(1, 1, 1, 0.30))
