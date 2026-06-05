class_name NpcAI
extends RefCounted
## npc_ai.gd
## Comportement "vivant" des habitants : déambulation autour d'un point d'ancrage
## (avec collisions), coups d'œil quand ils sont à l'arrêt, et petites bulles
## d'ambiance qui apparaissent de temps en temps. Partagé par la ville et le
## saloon. On opère directement sur le dictionnaire du PNJ (pas d'allocation).
##
## `blocked` : Callable(Vector2) -> bool (position infranchissable ?).

const SPEED := 58.0
const CHATTER := ["…", "*crache*", "Hmm.", "Sacrée chaleur.", "*siffle un air*",
	"Tch.", "Sale temps pour traîner.", "Belle journée pour un casse, hein ?",
	"*tousse*", "On dit que la banque est pleine à craquer..."]


static func update(npc: Dictionary, delta: float, blocked: Callable, rng: RandomNumberGenerator) -> void:
	if not npc.has("home"):
		npc["home"] = npc["pos"]
		npc["state"] = "idle"
		npc["timer"] = rng.randf_range(0.4, 2.2)
		npc["walk"] = 0.0
		npc["chat_t"] = rng.randf_range(3.0, 9.0)
		npc["bubble_until"] = 0.0
		npc["bubble"] = ""
		if not npc.has("wander"):
			npc["wander"] = 110.0
		if typeof(npc.get("facing")) != TYPE_VECTOR2:
			npc["facing"] = Vector2.DOWN

	npc["timer"] -= delta
	npc["chat_t"] -= delta
	var now := Time.get_ticks_msec() / 1000.0
	if npc["chat_t"] <= 0.0:
		npc["bubble"] = CHATTER[rng.randi() % CHATTER.size()]
		npc["bubble_until"] = now + 2.4
		npc["chat_t"] = rng.randf_range(7.0, 16.0)

	match npc["state"]:
		"walk":
			var to: Vector2 = npc["target"] - npc["pos"]
			if to.length() < 6.0:
				_rest(npc, rng)
			else:
				var dir := to.normalized()
				npc["facing"] = dir
				npc["walk"] += delta * 9.0
				var step := dir * SPEED * delta
				var moved := false
				var nx: Vector2 = npc["pos"] + Vector2(step.x, 0.0)
				if not blocked.call(nx):
					npc["pos"] = nx
					moved = true
				var ny: Vector2 = npc["pos"] + Vector2(0.0, step.y)
				if not blocked.call(ny):
					npc["pos"] = ny
					moved = true
				if not moved:
					_rest(npc, rng)
		_:  # idle
			npc["walk"] = 0.0
			if npc["timer"] <= 0.0:
				if float(npc["wander"]) >= 8.0:
					_pick_target(npc, blocked, rng)
				else:
					# Sédentaire (barman, pianiste) : il tourne juste la tête.
					npc["facing"] = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
					npc["timer"] = rng.randf_range(1.6, 3.6)


static func _rest(npc: Dictionary, rng: RandomNumberGenerator) -> void:
	npc["state"] = "idle"
	npc["walk"] = 0.0
	npc["timer"] = rng.randf_range(0.8, 2.8)


static func _pick_target(npc: Dictionary, blocked: Callable, rng: RandomNumberGenerator) -> void:
	for _i in range(6):
		var ang := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(30.0, float(npc["wander"]))
		var t: Vector2 = npc["home"] + Vector2.RIGHT.rotated(ang) * r
		if not blocked.call(t):
			npc["target"] = t
			npc["state"] = "walk"
			return
	npc["timer"] = rng.randf_range(1.0, 2.5)


## Bulle d'ambiance active ? (pour l'affichage).
static func bubble(npc: Dictionary) -> String:
	if npc.get("bubble_until", 0.0) > Time.get_ticks_msec() / 1000.0:
		return str(npc.get("bubble", ""))
	return ""
