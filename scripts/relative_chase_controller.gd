extends RefCounted
class_name RelativeChaseController
## relative_chase_controller.gd
## Poursuite RELATIVE (CLAUDE.md §5) : la cible (train/diligence) avance en
## continu ; le joueur à cheval se déplace PAR RAPPORT à elle — latéralement
## (gauche/droite) et en avançant/reculant (réduire/creuser l'écart). Le monde
## défile parce que la caméra suit la cible.
##
## Système autonome et composable : il ne connaît ni le contenu (wagons, coffres),
## ni le rendu. Il maintient juste l'offset du joueur dans le repère de la cible
## (x = le long de la course, y = latéral) et le borne à une bande jouable.

const LANE_HALF := 230.0    # amplitude latérale max (de part et d'autre de la cible)
const AHEAD_MAX := 140.0    # on peut se porter un peu DEVANT la cible
const BEHIND_MAX := 420.0   # ...ou décrocher en arrière (au-delà = distancé)
const MOVE_SPEED := 260.0   # vitesse de repositionnement relatif
const CATCH_X := 40.0       # |rel.x| sous lequel on est "à hauteur" de la cible

# Bornes de la bande, réglables PAR INSTANCE (un train est plus long qu'une
# diligence). Par défaut = les constantes ci-dessus -> comportement inchangé.
var lane_half := LANE_HALF
var ahead_max := AHEAD_MAX
var behind_max := BEHIND_MAX
var move_speed := MOVE_SPEED

# Offset dans le repère de la cible : x le long de la course, y latéral.
# Départ : un peu en arrière, sur le côté.
var rel := Vector2(-300.0, 120.0)


## Met à jour l'offset relatif depuis l'entrée (direction monde alignée écran).
## `input.x` = avancer(+)/reculer(-), `input.y` = latéral.
func update(delta: float, input: Vector2) -> void:
	rel += input.limit_length(1.0) * move_speed * delta
	rel.x = clampf(rel.x, -behind_max, ahead_max)
	rel.y = clampf(rel.y, -lane_half, lane_half)


## Position MONDE du joueur, étant donné la cible et sa direction de course.
func player_world(target_pos: Vector2, track_dir: Vector2) -> Vector2:
	var dir := track_dir.normalized() if track_dir.length() > 0.001 else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)   # latéral (90° à gauche de la course)
	return target_pos + dir * rel.x + perp * rel.y


## Écart le long de la course (>0 = en arrière de la cible, 0 = à hauteur).
func gap() -> float:
	return -rel.x


## Vrai quand le joueur est arrivé à hauteur de la cible (zone d'interaction).
func caught_up() -> bool:
	return absf(rel.x) <= CATCH_X


## A-t-on été distancé (collé à la limite arrière) ?
func is_distanced() -> bool:
	return rel.x <= -behind_max + 1.0
