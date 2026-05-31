extends Node
## InputManager (autoload)
## Fusionne les entrées clavier (actions du project.godot) et les entrées
## tactiles (joystick virtuel + bouton interaction de mobile_controls.gd).
## Le reste du jeu ne lit QUE cet autoload, jamais Input directement.

## Vecteur du joystick virtuel, alimenté par mobile_controls chaque frame.
var _touch_move := Vector2.ZERO
## Bouton interaction tactile : passe à true une frame quand pressé.
var _touch_interact_pressed := false
## Bouton interaction tactile maintenu (pour remplir la barre du coffre).
var _touch_interact_held := false


## Direction de déplacement normalisée-bornée (clavier + tactile fusionnés).
func get_move_vector() -> Vector2:
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var combined := keyboard + _touch_move
	if combined.length() > 1.0:
		combined = combined.normalized()
	return combined


## Vrai une seule frame quand l'interaction est demandée (E ou bouton tactile).
func is_interact_just_pressed() -> bool:
	if Input.is_action_just_pressed("interact"):
		return true
	if _touch_interact_pressed:
		_touch_interact_pressed = false
		return true
	return false


## Vrai tant que l'interaction est maintenue (E maintenu ou bouton tactile tenu).
func is_interact_held() -> bool:
	return Input.is_action_pressed("interact") or _touch_interact_held


func is_pause_just_pressed() -> bool:
	return Input.is_action_just_pressed("pause")


# --- API appelée par mobile_controls.gd ---

func set_touch_move(v: Vector2) -> void:
	_touch_move = v

func trigger_touch_interact() -> void:
	_touch_interact_pressed = true

func set_touch_interact_held(held: bool) -> void:
	_touch_interact_held = held
	if held:
		_touch_interact_pressed = true
