extends CharacterBody2D
## ally_ai.gd
## Coéquipier recruté (attaque de diligence) : suit le joueur, vise le garde le
## plus proche et tire des balles "friendly" (qui abattent les gardes). Immunisé
## aux balles ennemies (elles ne ciblent que le joueur). Rendu par l'IsoRenderer.

var player: Node2D = null
var guards: Array = []
var bullet_system: Node = null
var marksman := false
var pal_kind := "ally"     # pour le rendu (palette)

const SPEED := 150.0
const MUZZLE := 16.0

var facing := Vector2.DOWN
var walk_phase := 0.0
var _fire_cd := 0.0


func _physics_process(delta: float) -> void:
	if player == null:
		return
	var to_player := player.global_position - global_position
	var d := to_player.length()
	var target: Node = _nearest_guard()
	# Déplacement : reste à portée du joueur, se rapproche si trop loin.
	var move := Vector2.ZERO
	if d > 170.0:
		move = to_player.normalized()
	elif target == null and d > 100.0:
		move = to_player.normalized() * 0.6
	if target != null:
		facing = (target.global_position - global_position).normalized()
	elif move.length() > 0.05:
		facing = move.normalized()
	velocity = move * SPEED
	move_and_slide()
	walk_phase += delta * 10.0 if move.length() > 0.05 else 0.0
	# Tir sur le garde à portée.
	_fire_cd = max(0.0, _fire_cd - delta)
	var rng_range := 360.0 if marksman else 240.0
	if target != null and _fire_cd <= 0.0 and bullet_system != null \
			and global_position.distance_to(target.global_position) < rng_range:
		var aim: Vector2 = target.global_position - global_position
		bullet_system.spawn(global_position + aim.normalized() * MUZZLE, aim, true)
		_fire_cd = 0.6 if marksman else 0.95


func _nearest_guard() -> Node:
	var best: Node = null
	var bd := INF
	for g in guards:
		if is_instance_valid(g) and g.active:
			var dd: float = global_position.distance_to(g.global_position)
			if dd < bd:
				bd = dd
				best = g
	return best


func get_facing() -> Vector2:
	return facing
