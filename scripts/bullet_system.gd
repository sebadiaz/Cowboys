extends Node2D
## bullet_system.gd
## Gère les balles en coordonnées cartésiennes (la physique du jeu). Le rendu
## isométrique est fait par iso_renderer (qui lit la liste `bullets`).
## Balles "friendly" (joueur) -> abattent les gardes. Balles ennemies -> blessent
## le joueur. Les murs (couche 1) bloquent les balles (raycast).

signal guard_killed(guard: Node)
signal player_hit()

const SPEED := 620.0
const HIT_RADIUS := 20.0
const MAX_RANGE := 900.0
const WALL_MASK := 1

# Chaque balle : { "pos": Vector2, "dir": Vector2, "friendly": bool, "dist": float }
var bullets: Array[Dictionary] = []

var guards: Array = []
var player: Node2D = null
var active := true


## Crée une balle à `pos` dans la direction `dir`.
func spawn(pos: Vector2, dir: Vector2, friendly: bool) -> void:
	if dir.length() < 0.01:
		return
	bullets.append({"pos": pos, "dir": dir.normalized(), "friendly": friendly, "dist": 0.0})


func _physics_process(delta: float) -> void:
	if not active or bullets.is_empty():
		return
	var space := get_world_2d().direct_space_state
	var step := SPEED * delta
	var survivors: Array[Dictionary] = []
	for b in bullets:
		var from: Vector2 = b["pos"]
		var to: Vector2 = from + b["dir"] * step
		# Mur sur la trajectoire ?
		var query := PhysicsRayQueryParameters2D.create(from, to, WALL_MASK)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		if not space.intersect_ray(query).is_empty():
			continue  # balle absorbée par le mur
		b["pos"] = to
		b["dist"] += step
		if b["dist"] > MAX_RANGE:
			continue
		# Impacts.
		if b["friendly"]:
			var hit := false
			for g in guards:
				if is_instance_valid(g) and g.active and to.distance_to(g.global_position) < HIT_RADIUS:
					guard_killed.emit(g)
					hit = true
					break
			if hit:
				continue
		else:
			if is_instance_valid(player) and not player.is_caught \
					and to.distance_to(player.global_position) < HIT_RADIUS:
				player_hit.emit()
				continue
		survivors.append(b)
	bullets = survivors


func stop() -> void:
	active = false
	bullets.clear()
