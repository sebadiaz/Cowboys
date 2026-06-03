extends Node2D
## effects.gd
## Effets visuels de la mission (rendu en espace écran, comme iso_renderer) :
## muzzle flash, étincelles d'impact, poussière de pas, douilles éjectées,
## screen-shake (via la position du renderer) et flash plein écran (dégâts/alarme).
## Reçoit les positions MONDE et les projette en iso, comme le renderer.

var iso_offset := Vector2.ZERO        # décalage de projection (0 quand le noeud est zoomé)
var shake_amount: float = 0.0

# Particule : {pos(screen), vel, life, max_life, size, color, kind}
var _parts: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	z_index = 100   # au-dessus du décor


func _process(delta: float) -> void:
	# Décroissance des particules.
	var alive: Array[Dictionary] = []
	for p in _parts:
		p["life"] -= delta
		if p["life"] <= 0.0:
			continue
		p["vel"] *= 0.90
		if p["kind"] == "shell" or p["kind"] == "dust":
			p["vel"].y += 120.0 * delta   # petite gravité écran
		p["pos"] += p["vel"] * delta
		alive.append(p)
	_parts = alive
	# Décroissance du shake.
	shake_amount = max(0.0, shake_amount - delta * 40.0)
	queue_redraw()


# --- API (positions MONDE) ---

func muzzle_flash(world_pos: Vector2, dir: Vector2) -> void:
	var s := _proj(world_pos)
	var d := _screen_dir(world_pos, dir)
	# Éclat jaune.
	for i in range(8):
		var a := d.angle() + _rng.randf_range(-0.5, 0.5)
		var spd := _rng.randf_range(80, 220)
		_parts.append(_mk(s, Vector2.RIGHT.rotated(a) * spd, _rng.randf_range(0.06, 0.16),
				_rng.randf_range(2.5, 4.5), Color(1.0, 0.92, 0.45), "spark"))
	# Fumée.
	for i in range(3):
		_parts.append(_mk(s + d * 6, d * 30 + _rand_v(12), _rng.randf_range(0.25, 0.5),
				_rng.randf_range(4, 7), Color(0.8, 0.8, 0.8, 0.5), "smoke"))
	# Douille éjectée latéralement.
	var side := d.rotated(PI / 2) * (1 if _rng.randf() < 0.5 else -1)
	_parts.append(_mk(s, side * 90 + Vector2(0, -60), 0.6, 2.5, Color(0.85, 0.7, 0.2), "shell"))
	add_shake(3.0)


func impact_spark(world_pos: Vector2, dir: Vector2, friendly: bool) -> void:
	var s := _proj(world_pos)
	var base := Color(1.0, 0.6, 0.2) if friendly else Color(1.0, 0.3, 0.25)
	for i in range(10):
		var a := _rng.randf_range(0, TAU)
		var spd := _rng.randf_range(60, 200)
		_parts.append(_mk(s, Vector2.RIGHT.rotated(a) * spd, _rng.randf_range(0.1, 0.3),
				_rng.randf_range(2, 4), base, "spark"))
	add_shake(4.0)


func wall_puff(world_pos: Vector2) -> void:
	var s := _proj(world_pos)
	for i in range(6):
		_parts.append(_mk(s, _rand_v(70), _rng.randf_range(0.15, 0.35),
				_rng.randf_range(3, 5), Color(0.55, 0.42, 0.3, 0.7), "smoke"))


func loot_pickup(world_pos: Vector2) -> void:
	var s := _proj(world_pos)
	# Gerbe dorée qui jaillit vers le haut.
	for i in range(14):
		var a := -PI / 2 + _rng.randf_range(-0.9, 0.9)
		var spd := _rng.randf_range(70, 190)
		_parts.append(_mk(s, Vector2.RIGHT.rotated(a) * spd, _rng.randf_range(0.3, 0.6),
				_rng.randf_range(2.5, 4.5), Color(1.0, 0.85, 0.25), "shell"))


func safe_burst(world_pos: Vector2) -> void:
	var s := _proj(world_pos)
	for i in range(18):
		var a := _rng.randf_range(0, TAU)
		var spd := _rng.randf_range(60, 200)
		var col := Color(1.0, 0.9, 0.4) if _rng.randf() < 0.6 else Color(0.8, 0.8, 0.85)
		_parts.append(_mk(s, Vector2.RIGHT.rotated(a) * spd, _rng.randf_range(0.3, 0.7),
				_rng.randf_range(2.5, 5.0), col, "spark"))
	add_shake(5.0)


func foot_dust(world_pos: Vector2) -> void:
	var s := _proj(world_pos)
	_parts.append(_mk(s + Vector2(0, -2), _rand_v(18) + Vector2(0, -10),
			_rng.randf_range(0.2, 0.4), _rng.randf_range(2.5, 4), Color(0.7, 0.6, 0.45, 0.5), "dust"))


func add_shake(amount: float) -> void:
	shake_amount = min(14.0, shake_amount + amount)


## Décalage de tremblement à appliquer au renderer (lu par mission_manager).
func get_shake_offset() -> Vector2:
	if shake_amount <= 0.01:
		return Vector2.ZERO
	return Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * shake_amount


# --- interne ---

func _mk(pos: Vector2, vel: Vector2, life: float, size: float, col: Color, kind: String) -> Dictionary:
	return {"pos": pos, "vel": vel, "life": life, "max_life": life, "size": size, "color": col, "kind": kind}


func _rand_v(speed: float) -> Vector2:
	return Vector2.RIGHT.rotated(_rng.randf_range(0, TAU)) * _rng.randf_range(speed * 0.3, speed)


func _proj(world_pos: Vector2) -> Vector2:
	return Iso.project(world_pos) + iso_offset + Vector2(0, -16)


func _screen_dir(world_pos: Vector2, dir: Vector2) -> Vector2:
	var d := Iso.project(world_pos + dir) - Iso.project(world_pos)
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT


func _draw() -> void:
	for p in _parts:
		var t: float = clampf(p["life"] / p["max_life"], 0.0, 1.0)
		var c: Color = p["color"]
		c.a *= t
		if p["kind"] == "shell":
			draw_rect(Rect2(p["pos"] - Vector2(1.5, 1.5), Vector2(3, 3)), c)
		else:
			draw_circle(p["pos"], p["size"] * (0.6 + 0.4 * t), c)
