extends RefCounted
class_name HorseController
## horse_controller.gd
## La MONTURE seule (CLAUDE.md §5) : état monté/à pied, vitesse et inertie.
## Système composable et autonome : il ne connaît ni la ville, ni les poursuites.
## L'appelant fournit l'entrée (direction monde) et applique la vélocité retournée
## via son propre move_and_slide (les collisions restent au moteur appelant).

const SPEED := 470.0       # vitesse de pointe (≈ 1.9× le joueur à pied)
const ACCEL := 1500.0      # montée en vitesse (le galop se lance progressivement)
const BRAKE := 1100.0      # décélération quand on lâche la direction (inertie)
const MOUNT_RADIUS := 90.0 # distance pour monter

var mounted := false
var vel := Vector2.ZERO
var facing := Vector2.DOWN
var rest_pos := Vector2.ZERO   # où le cheval attend quand on est descendu
var gallop := 0.0              # 0..1 : intensité du galop (poussière, balancement)


func can_mount(player_pos: Vector2) -> bool:
	return not mounted and player_pos.distance_to(rest_pos) < MOUNT_RADIUS


## Monte : le cheval rejoint le joueur (on l'enfourche sur place).
func mount() -> void:
	mounted = true
	vel = Vector2.ZERO
	gallop = 0.0


## Descend : le cheval reste là où on saute. Retourne sa position de repos.
func dismount(at: Vector2) -> Vector2:
	mounted = false
	vel = Vector2.ZERO
	gallop = 0.0
	rest_pos = at
	return rest_pos


## Vélocité voulue avec inertie. `input_dir` = direction monde (peut être nulle).
## Les collisions sont gérées par l'appelant (move_and_slide).
func compute_velocity(delta: float, input_dir: Vector2) -> Vector2:
	var target: Vector2 = input_dir.limit_length(1.0) * SPEED
	var rate: float = ACCEL if input_dir.length() > 0.05 else BRAKE
	vel = vel.move_toward(target, rate * delta)
	if vel.length() > 8.0:
		facing = vel.normalized()
	gallop = clampf(vel.length() / SPEED, 0.0, 1.0)
	return vel
