extends RefCounted
class_name WantedSystem
## wanted_system.gd  (Lot 14)
## La PRIME sur ta tête prend vie : au-delà d'un seuil de notoriété, des chasseurs
## de primes apparaissent aux bords de la ville et te traquent. Système isolé : il
## ne gère QUE la logique (spawn, poursuite, prise). Le rendu et les conséquences
## restent à l'appelant (town.gd). On lui fournit la position joueur + un test de
## collision (Callable) ; il bouge les chasseurs et signale une capture.

const THRESHOLD := 4         # notoriété mini pour déclencher la traque
const HUNTER_SPEED := 205.0  # < joueur à pied (250), << cheval (470) -> on peut fuir
const CATCH_DIST := 30.0
const SPAWN_INTERVAL := 3.2

var hunters: Array[Dictionary] = []   # {pos, facing}
var grace := 0.0                       # répit après une prise (pas de capture)
var _spawn_cd := 1.2
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func active(noto: int) -> bool:
	return noto >= THRESHOLD


func bounty(noto: int) -> int:
	return noto * 300


func max_hunters(noto: int) -> int:
	if noto < THRESHOLD:
		return 0
	return clampi(1 + (noto - THRESHOLD) / 3, 1, 3)


## Met à jour la traque ; retourne true si un chasseur attrape le joueur.
func update(delta: float, player_pos: Vector2, noto: int, bounds: Rect2, blocked: Callable) -> bool:
	if grace > 0.0:
		grace = maxf(0.0, grace - delta)
	var target := max_hunters(noto)
	while hunters.size() > target:
		hunters.pop_back()
	_spawn_cd -= delta
	if hunters.size() < target and _spawn_cd <= 0.0:
		_spawn_cd = SPAWN_INTERVAL
		hunters.append({"pos": _edge_spawn(player_pos, bounds), "facing": Vector2.DOWN})
	var caught := false
	for h in hunters:
		var dir: Vector2 = (player_pos - (h["pos"] as Vector2)).normalized()
		h["pos"] = _try_move(h["pos"], dir, HUNTER_SPEED * delta, blocked)
		if dir.length() > 0.01:
			h["facing"] = dir
		if grace <= 0.0 and (h["pos"] as Vector2).distance_to(player_pos) < CATCH_DIST:
			caught = true
	return caught


## Après une prise : on disperse et on laisse un répit.
func scatter(repit := 4.0) -> void:
	hunters.clear()
	grace = repit
	_spawn_cd = repit


func reset() -> void:
	hunters.clear()
	grace = 0.0
	_spawn_cd = 1.2


# --- interne ---

func _try_move(pos: Vector2, dir: Vector2, dist: float, blocked: Callable) -> Vector2:
	# Cherche le joueur ; contourne un obstacle en pivotant la direction.
	for ang in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var np: Vector2 = pos + dir.rotated(ang) * dist
		if not blocked.call(np):
			return np
	return pos


func _edge_spawn(player_pos: Vector2, b: Rect2) -> Vector2:
	for i in range(12):
		var p: Vector2
		match _rng.randi() % 4:
			0: p = Vector2(_rng.randf_range(b.position.x, b.end.x), b.position.y + 40.0)
			1: p = Vector2(_rng.randf_range(b.position.x, b.end.x), b.end.y - 40.0)
			2: p = Vector2(b.position.x + 40.0, _rng.randf_range(b.position.y, b.end.y))
			_: p = Vector2(b.end.x - 40.0, _rng.randf_range(b.position.y, b.end.y))
		if p.distance_to(player_pos) > 520.0:
			return p
	return b.position + Vector2(60.0, 60.0)
