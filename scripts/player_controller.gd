extends CharacterBody2D
## player_controller.gd
## Cowboy contrôlable en 8 directions. Suit InputManager (clavier + tactile).
## Ramasse le butin, peut être capturé par un garde en alerte.

signal loot_changed(loot_bags: int, loot_value: int)
signal caught()

const SPEED := 220.0
const BODY_RADIUS := 14.0

var loot_bags: int = 0
var loot_value: int = 0
var is_caught: bool = false
var facing := Vector2.DOWN


func _physics_process(_delta: float) -> void:
	if is_caught:
		velocity = Vector2.ZERO
		return
	var dir := InputManager.get_move_vector()
	velocity = dir * SPEED
	if dir.length() > 0.05:
		facing = dir.normalized()
		queue_redraw()
	move_and_slide()


## Ajoute un sac de butin (appelé par LootBag via mission_manager).
func add_loot(value: int) -> void:
	loot_bags += 1
	loot_value += value
	loot_changed.emit(loot_bags, loot_value)


## Bonus de valeur du coffre (sans incrémenter le nombre de sacs).
func add_safe_reward(value: int) -> void:
	loot_value += value
	loot_changed.emit(loot_bags, loot_value)


func has_loot() -> bool:
	return loot_bags > 0


func get_caught() -> void:
	if is_caught:
		return
	is_caught = true
	velocity = Vector2.ZERO
	caught.emit()


func _draw() -> void:
	# Ombre portée.
	draw_circle(Vector2(0, 6), BODY_RADIUS, Color(0, 0, 0, 0.25))
	# Corps marron.
	draw_circle(Vector2.ZERO, BODY_RADIUS, Color(0.45, 0.27, 0.13))
	# Chapeau (couronne + bord), décalé vers la direction regardée.
	var hat_offset := facing * 4.0
	draw_circle(hat_offset, BODY_RADIUS + 3.0, Color(0.30, 0.18, 0.08))
	draw_circle(hat_offset, BODY_RADIUS - 3.0, Color(0.38, 0.23, 0.10))
	# Petite étoile claire pour repérer l'avant.
	draw_circle(facing * (BODY_RADIUS - 2.0), 3.0, Color(0.95, 0.85, 0.55))
