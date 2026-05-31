extends Node2D
## vision_cone.gd
## Cône de vision visible d'un garde. Le garde fait pivoter ce noeud vers sa
## direction de regard ; le cône se dessine en coordonnées locales (+X = avant).
## Couleur : jaune (calme) → orange (suspect) → rouge (alerte).
## Détection = distance + angle + ligne de vue (raycast contre les murs).

@export var view_distance: float = 190.0
@export var view_angle_deg: float = 34.0  # demi-angle

const WALL_MASK := 1  # couche de collision des murs

var _fill := Color(1, 1, 0, 0.16)
var _edge := Color(1, 1, 0, 0.30)


## Met à jour la couleur selon l'état de détection (0 calme → 1 alerte).
func set_alert(ratio: float, is_alert: bool) -> void:
	if is_alert:
		_fill = Color(1.0, 0.15, 0.15, 0.30)
		_edge = Color(1.0, 0.2, 0.2, 0.5)
	elif ratio > 0.05:
		_fill = Color(1.0, 0.55, 0.0, 0.24)
		_edge = Color(1.0, 0.6, 0.1, 0.45)
	else:
		_fill = Color(1.0, 1.0, 0.0, 0.16)
		_edge = Color(1.0, 1.0, 0.2, 0.30)
	queue_redraw()


## Le point monde est-il visible depuis l'origine du cône ?
func can_see(target_global: Vector2) -> bool:
	var origin := global_position
	var to_target := target_global - origin
	var dist := to_target.length()
	if dist > view_distance or dist < 1.0:
		return false
	# Angle entre l'avant du cône (global_rotation) et la cible.
	var forward := Vector2.RIGHT.rotated(global_rotation)
	if forward.angle_to(to_target) > deg_to_rad(view_angle_deg):
		return false
	# Ligne de vue : un mur entre le garde et le joueur bloque la vision.
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(origin, target_global, WALL_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	return hit.is_empty()


func _draw() -> void:
	var half := deg_to_rad(view_angle_deg)
	var steps := 14
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i in range(steps + 1):
		var a: float = lerpf(-half, half, float(i) / float(steps))
		pts.append(Vector2.RIGHT.rotated(a) * view_distance)
	draw_colored_polygon(pts, _fill)
	# Contour des deux bords du cône.
	draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(-half) * view_distance, _edge, 1.5)
	draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(half) * view_distance, _edge, 1.5)
