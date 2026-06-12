extends Node2D
## train_chase.gd  (Lot 19)
## Braquage de TRAIN : même base que la diligence (RelativeChaseController +
## HorseController), mais la cible est une LOCOMOTIVE tirant plusieurs WAGONS en
## file. Le joueur longe le convoi et pille les wagons un par un (avancer/reculer
## choisit le wagon, maintien E à hauteur) ; des gardes postés sur les toits
## ripostent ; l'équipe (CrewScreen) chevauche et tire. Le wagon d'OR au bout est
## l'objectif ; ensuite on décroche pour fuir. Réutilise HUD/résultat/bande fidèle.

const TRAIN_SPEED := 320.0
const BULLET_SPEED := 950.0
const GUARD_FIRE := 1.9
const ALLY_FIRE := 1.3
const LOOT_TIME := 2.4
const LOCO_HALF := 48.0
const CAR_LEN := 120.0
const CAR_GAP := 10.0
const RAIL_HALF := 30.0

var _chase := RelativeChaseController.new()
var _horse := HorseController.new()
var _hud: CanvasLayer

var _loco_pos := Vector2.ZERO
var _track_dir := Vector2.RIGHT
var _player_pos := Vector2.ZERO
var _facing := Vector2.RIGHT
var _ride := 0.0
var _smoke := 0.0
var _cam := Vector2.ZERO
var _scale := 1.6

var _hp := 3
var _max_hp := 3
var _dmg_cd := 0.0
var _fire_cd := 0.0

var _cars: Array[Dictionary] = []      # {along, value, looted, progress, gold}
var _guards: Array[Dictionary] = []    # {along, side, hp, fire_cd, alive, facing}
var _allies: Array[Dictionary] = []
var _bullets: Array[Dictionary] = []
var _corpses: Array[Dictionary] = []

var _loot_value := 0
var _loot_bags := 0
var _gold_looted := false
var _elapsed := 0.0
var _over := false
var _escaping := false
var _train_len := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Iso.top_down = true
	_rng.randomize()
	_horse.mounted = true
	# Bande élargie : un train est long, il faut pouvoir longer tout le convoi.
	_chase.behind_max = 600.0
	_chase.ahead_max = 120.0
	_chase.lane_half = 210.0
	_chase.rel = Vector2(-200.0, 130.0)
	_max_hp = (5 if GameManager.assist else 3) + SaveManager.hp_bonus()
	_max_hp += GameManager.crew_count_role("medic")
	_hp = _max_hp
	_build_train()
	_player_pos = _chase.player_world(_loco_pos, _track_dir)
	var vp := get_viewport_rect().size
	_scale = clampf(minf(vp.x, vp.y) / 480.0, 1.1, 2.2)
	scale = Vector2(_scale, _scale)
	_spawn_allies()
	_build_hud()
	AudioManager.play_music("tension")


func _build_train() -> void:
	# 3 wagons de fret + 1 wagon d'or au bout. Position le long de la course
	# (négative = derrière la loco).
	var n_cargo := 3
	for i in range(n_cargo + 1):
		var along := -(LOCO_HALF + CAR_GAP + CAR_LEN * 0.5 + i * (CAR_LEN + CAR_GAP))
		var gold := i == n_cargo
		_cars.append({"along": along, "value": (900 if gold else 280), "looted": false,
				"progress": 0.0, "gold": gold})
	_train_len = LOCO_HALF + (n_cargo + 1) * (CAR_LEN + CAR_GAP)
	# Gardes postés sur les toits (wagon d'or + un wagon de fret), +1 par notoriété.
	var guard_cars := [n_cargo, 1]
	var extra := clampi(SaveManager.notoriety / 2, 0, 2)
	for k in range(extra):
		guard_cars.append((k * 2) % n_cargo)
	for ci in guard_cars:
		var a: float = _cars[ci]["along"]
		_guards.append({"along": a, "side": (1.0 if _guards.size() % 2 == 0 else -1.0) * 18.0,
				"hp": 2, "fire_cd": _rng.randf_range(0.6, GUARD_FIRE), "alive": true, "facing": Vector2.LEFT})


func _build_hud() -> void:
	_hud = preload("res://scenes/HUD.tscn").instantiate()
	add_child(_hud)
	_hud.set_health(_hp, _max_hp)
	_hud.set_loot(0, 0)
	_hud.set_money(SaveManager.total_money)
	_hud.set_alarm(0.0)
	_hud.set_objective("Longe le train et PILLE les wagons (E à hauteur) — l'OR au bout")
	if not _allies.is_empty():
		_hud.show_toast("ÉQUIPE EN SELLE ! (%d)" % _allies.size())


func _spawn_allies() -> void:
	for c in GameManager.crew:
		var role := str(c.get("role", ""))
		if role == "gunman" or role == "marksman":
			_allies.append({"off": Vector2(_rng.randf_range(-60, -10), _rng.randf_range(-80, 80)),
				"hp": 3, "fire_cd": _rng.randf_range(0.3, ALLY_FIRE), "alive": true,
				"name": str(c.get("name", "")), "role": role, "facing": Vector2.RIGHT})


func _process(delta: float) -> void:
	Iso.top_down = true
	if _over:
		_advance_bullets(delta)
		_update_camera(delta)
		queue_redraw()
		return
	_elapsed += delta
	_smoke += delta
	_dmg_cd = maxf(0.0, _dmg_cd - delta)
	# Le train avance en continu (légère ondulation de la voie).
	_track_dir = Vector2.RIGHT.rotated(sin(_loco_pos.x * 0.0005) * 0.12)
	_loco_pos += _track_dir * TRAIN_SPEED * delta
	var input := InputManager.get_move_vector()
	_chase.update(delta, input)
	var np := _chase.player_world(_loco_pos, _track_dir)
	var mv := np - _player_pos
	if mv.length() > 1.0:
		_facing = mv.normalized()
	_player_pos = np
	_ride += delta * 14.0
	_update_loot(delta)
	_update_combat(delta)
	_advance_bullets(delta)
	_update_camera(delta)
	_check_end()
	if _hud != null:
		_hud.set_health(_hp, _max_hp)
		_hud.set_loot(_loot_bags, _loot_value)
	queue_redraw()


# --- Pillage par wagon ---

func _nearest_car() -> int:
	# Wagon non pillé dont la position le long de la course est la plus proche
	# de celle du joueur (rel.x).
	var best := 1.0e20
	var idx := -1
	for i in range(_cars.size()):
		if _cars[i]["looted"]:
			continue
		var d := absf(_chase.rel.x - float(_cars[i]["along"]))
		if d < best:
			best = d
			idx = i
	return idx


func _update_loot(delta: float) -> void:
	var idx := _nearest_car()
	if idx < 0:
		return
	var car: Dictionary = _cars[idx]
	var aligned := absf(_chase.rel.x - float(car["along"])) < 52.0
	var side_ok := absf(_chase.rel.y) < 95.0
	if aligned and side_ok and InputManager.is_interact_held():
		car["progress"] = minf(1.0, float(car["progress"]) + delta / LOOT_TIME)
		if float(car["progress"]) >= 1.0:
			_loot_car(idx)


func _loot_car(idx: int) -> void:
	var car: Dictionary = _cars[idx]
	car["looted"] = true
	var val := int(int(car["value"]) * SaveManager.loot_mult())
	_loot_value += val
	_loot_bags += 1
	AudioManager.play("safe")
	if bool(car["gold"]):
		_gold_looted = true
		_escaping = true
		if _hud != null:
			_hud.show_toast("WAGON D'OR PILLÉ ! +%d $" % val)
			_hud.set_objective("DÉCROCHE ! Recule pour fuir le train")
	elif _hud != null:
		_hud.show_toast("Wagon pillé ! +%d $" % val)


# --- Combat (gardes de toit + alliés) ---

func _update_combat(delta: float) -> void:
	for g in _guards:
		if not g["alive"]:
			continue
		var gp := _guard_pos(g)
		g["facing"] = (_player_pos - gp).normalized()
		g["fire_cd"] = float(g["fire_cd"]) - delta
		if g["fire_cd"] <= 0.0 and gp.distance_to(_player_pos) < 400.0:
			_spawn_bullet(gp, (_player_pos - gp), false)
			g["fire_cd"] = GUARD_FIRE * (1.4 if GameManager.assist else 1.0)
	for a in _allies:
		if not a["alive"]:
			continue
		var ap: Vector2 = _player_pos + _rot(a["off"])
		a["fire_cd"] = float(a["fire_cd"]) - delta
		var tgt = _nearest_guard(ap)
		if tgt != null:
			a["facing"] = (tgt - ap).normalized()
			if a["fire_cd"] <= 0.0:
				_spawn_bullet(ap, (tgt - ap), true)
				a["fire_cd"] = ALLY_FIRE
	_fire_cd = maxf(0.0, _fire_cd - delta)
	if InputManager.is_fire_pressed() and _fire_cd <= 0.0:
		var aim = _nearest_guard(_player_pos)
		var dir: Vector2 = (aim - _player_pos) if aim != null else _track_dir
		_spawn_bullet(_player_pos + dir.normalized() * 18.0, dir, true)
		_fire_cd = 0.28


func _guard_pos(g: Dictionary) -> Vector2:
	return _loco_pos + _rot(Vector2(float(g["along"]), float(g["side"])))


func _spawn_bullet(pos: Vector2, dir: Vector2, friendly: bool) -> void:
	_bullets.append({"pos": pos, "vel": dir.normalized() * BULLET_SPEED, "friendly": friendly, "life": 0.9})


func _advance_bullets(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for b in _bullets:
		b["pos"] += b["vel"] * delta
		b["life"] = float(b["life"]) - delta
		if b["life"] <= 0.0:
			continue
		var hit := false
		if b["friendly"]:
			for g in _guards:
				if g["alive"] and _guard_pos(g).distance_to(b["pos"]) < 16.0:
					g["hp"] = int(g["hp"]) - 1
					hit = true
					if int(g["hp"]) <= 0:
						g["alive"] = false
						_corpses.append({"pos": _guard_pos(g), "t": 0.0})
					break
		else:
			if not _over and _dmg_cd <= 0.0 and _player_pos.distance_to(b["pos"]) < 15.0:
				_hurt_player()
				hit = true
			if not hit:
				for a in _allies:
					if a["alive"] and (_player_pos + _rot(a["off"])).distance_to(b["pos"]) < 15.0:
						a["hp"] = int(a["hp"]) - 1
						hit = true
						if int(a["hp"]) <= 0:
							a["alive"] = false
							_corpses.append({"pos": _player_pos + _rot(a["off"]), "t": 0.0})
							if _hud != null:
								_hud.show_toast("ALLIÉ À TERRE !")
						break
		if not hit:
			alive.append(b)
	_bullets = alive
	for c in _corpses:
		c["t"] = float(c["t"]) + delta


func _hurt_player() -> void:
	_hp = maxi(0, _hp - 1)
	_dmg_cd = 0.8 if GameManager.assist else 0.45
	AudioManager.play("hit_player", -4.0)
	if _hud != null and _hp > 0:
		_hud.flash(Color(1, 0, 0, 0.35))


func _nearest_guard(from: Vector2):
	var best := 1.0e20
	var pos = null
	for g in _guards:
		if not g["alive"]:
			continue
		var gp := _guard_pos(g)
		var d := from.distance_to(gp)
		if d < best:
			best = d
			pos = gp
	return pos


# --- Fin ---

func _check_end() -> void:
	if _over:
		return
	if _hp <= 0:
		_end(false)
		return
	if _escaping and _chase.is_distanced():
		_end(true)


func _end(success: bool) -> void:
	_over = true
	if success:
		_promote_crew_to_gang()
	if _hud != null:
		_hud.show_toast("FUITE RÉUSSIE !" if success else "ABATTU ! ÉCHEC")
	AudioManager.play("win" if success else "lose", 2.0)
	AudioManager.stop_music()
	await get_tree().create_timer(0.9).timeout
	GameManager.finish_mission(success, _loot_value, _loot_bags, _score())


func _promote_crew_to_gang() -> void:
	var alive := {}
	for a in _allies:
		if a["alive"]:
			alive[str(a["name"])] = true
	for c in GameManager.crew:
		var role := str(c.get("role", ""))
		var nm := str(c.get("name", ""))
		if role == "gunman" or role == "marksman":
			if alive.has(nm):
				SaveManager.add_loyal(nm, role)
		else:
			SaveManager.add_loyal(nm, role)


func _score() -> Dictionary:
	var kills := 0
	for g in _guards:
		if not g["alive"]:
			kills += 1
	var time_bonus: int = maxi(0, int(round((150.0 - _elapsed) * 2.0)))
	var crew := 200 * GameManager.crew_count_role("scout") + 120 * _live_allies()
	var guard_bonus := 90 * kills
	return {
		"loot": _loot_value, "stealth": 0, "time": time_bonus,
		"contract": guard_bonus, "crew": crew,
		"total": _loot_value + time_bonus + crew + guard_bonus,
	}


func _live_allies() -> int:
	var n := 0
	for a in _allies:
		if a["alive"]:
			n += 1
	return n


# --- Rendu ---

func _rot(off: Vector2) -> Vector2:
	var d := _track_dir.normalized()
	var perp := Vector2(-d.y, d.x)
	return d * off.x + perp * off.y


func _update_camera(delta: float) -> void:
	var vp := get_viewport_rect().size
	var train_mid := _loco_pos + _track_dir * (-_train_len * 0.5)
	var focus := _player_pos.lerp(train_mid, 0.3)
	_cam = _cam.lerp(vp * 0.5 - focus * _scale, clampf(delta * 8.0, 0.0, 1.0))
	position = _cam


func _draw() -> void:
	_draw_ground()
	_draw_rails()
	var items: Array[Dictionary] = []
	items.append({"y": _loco_pos.y - 9999.0, "k": "train"})   # le train sous tout le monde
	for g in _guards:
		if g["alive"]:
			var gp := _guard_pos(g)
			items.append({"y": gp.y, "k": "guard", "p": gp, "f": g["facing"]})
	for a in _allies:
		if a["alive"]:
			var ap: Vector2 = _player_pos + _rot(a["off"])
			items.append({"y": ap.y, "k": "ally", "p": ap, "f": a["facing"]})
	for c in _corpses:
		items.append({"y": c["pos"].y, "k": "corpse", "p": c["pos"]})
	items.append({"y": _player_pos.y, "k": "me"})
	items.sort_custom(func(a, b): return a["y"] < b["y"])
	for it in items:
		match it["k"]:
			"train": _draw_train()
			"guard": _draw_roof_guard(it["p"], it["f"])
			"ally": _draw_rider(it["p"], it["f"], Color(0.78, 1.05, 0.8), _pal_ally())
			"corpse": _draw_corpse(it["p"])
			"me": _draw_rider(_player_pos, _facing, Color(1.0, 0.92, 0.7), CharacterArt.hero_palette(), true)
	for b in _bullets:
		var p: Vector2 = b["pos"]
		var d: Vector2 = (b["vel"] as Vector2).normalized()
		var col := Color(1, 0.9, 0.4) if b["friendly"] else Color(1, 0.5, 0.25)
		draw_line(p - d * 15.0, p, Color(col.r, col.g, col.b, 0.5), 3.0)
		draw_circle(p, 3.0, col)
	_draw_overlay()


func _draw_ground() -> void:
	var perp := Vector2(-_track_dir.y, _track_dir.x)
	var step := 130.0
	var base := floorf(_loco_pos.x / step) * step
	for i in range(-10, 16):
		var x := base + i * step
		var c := Color(0.74, 0.60, 0.40) if int(roundf(x / step)) % 2 == 0 else Color(0.70, 0.55, 0.36)
		var center := Vector2(x, _loco_pos.y)
		var a := center + perp * 1100.0 - _track_dir * (step * 0.5)
		var bb := center - perp * 1100.0 - _track_dir * (step * 0.5)
		var cc := center - perp * 1100.0 + _track_dir * (step * 0.5)
		var dd := center + perp * 1100.0 + _track_dir * (step * 0.5)
		draw_colored_polygon(PackedVector2Array([a, dd, cc, bb]), c)


func _draw_rails() -> void:
	var d := _track_dir.normalized()
	var perp := Vector2(-d.y, d.x)
	var front := _loco_pos + d * 120.0
	var backlen := _train_len + 360.0
	# Traverses.
	var ties := int(backlen / 26.0)
	for i in range(ties):
		var c := front - d * (i * 26.0)
		draw_line(c - perp * (RAIL_HALF + 7.0), c + perp * (RAIL_HALF + 7.0), Color(0.34, 0.22, 0.12), 3.0)
	# Deux rails.
	for s in [-1.0, 1.0]:
		draw_line(front + perp * (RAIL_HALF * s), front - d * backlen + perp * (RAIL_HALF * s),
				Color(0.55, 0.55, 0.6), 3.0)


func _draw_train() -> void:
	var d := _track_dir.normalized()
	var perp := Vector2(-d.y, d.x)
	# Wagons (de l'arrière vers l'avant pour le recouvrement).
	for i in range(_cars.size() - 1, -1, -1):
		_draw_car(_cars[i], d, perp)
	# Locomotive.
	_draw_loco(d, perp)


func _draw_car(car: Dictionary, d: Vector2, perp: Vector2) -> void:
	var c := _loco_pos + d * float(car["along"])
	var hl := CAR_LEN * 0.5
	var hw := 26.0
	var looted: bool = car["looted"]
	var gold: bool = car["gold"]
	var body := Color(0.30, 0.22, 0.14) if not gold else Color(0.42, 0.32, 0.14)
	if looted:
		body = body.darkened(0.25)
	var poly := PackedVector2Array([
		c - d * hl - perp * hw, c + d * hl - perp * hw, c + d * hl + perp * hw, c - d * hl + perp * hw])
	draw_colored_polygon(PackedVector2Array([poly[0] + Vector2(3, 4), poly[1] + Vector2(3, 4),
			poly[2] + Vector2(3, 4), poly[3] + Vector2(3, 4)]), Color(0, 0, 0, 0.22))
	draw_colored_polygon(poly, body)
	draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), body.darkened(0.4), 3.0)
	# Toit (planches).
	for t in [0.3, 0.5, 0.7]:
		draw_line(poly[0].lerp(poly[1], t), poly[3].lerp(poly[2], t), body.lightened(0.06), 1.0)
	# Roues.
	for du in [-0.6, 0.6]:
		for su in [-1.0, 1.0]:
			draw_circle(c + d * (hl * du) + perp * (hw + 3.0) * su, 7.0, Color(0.14, 0.10, 0.07))
	# Coffre / pastille d'or au centre + jauge de pillage.
	var mark := Color(0.5, 0.42, 0.25) if looted else (Color(0.96, 0.82, 0.30) if gold else Color(0.75, 0.66, 0.4))
	draw_circle(c, 9.0 if not gold else 11.0, mark)
	if float(car["progress"]) > 0.0 and not looted:
		var bw := 50.0
		var head := c + Vector2(0, -hw - 16.0)
		draw_rect(Rect2(head + Vector2(-bw * 0.5, -4), Vector2(bw, 6)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(head + Vector2(-bw * 0.5, -4), Vector2(bw * float(car["progress"]), 6)), Color(0.95, 0.8, 0.2))
	if gold and not looted:
		_text(c + Vector2(0, -hw - 22.0), "WAGON D'OR", 12, Color(1, 0.9, 0.45))


func _draw_loco(d: Vector2, perp: Vector2) -> void:
	var c := _loco_pos
	var hl := LOCO_HALF
	var hw := 28.0
	var poly := PackedVector2Array([
		c - d * hl - perp * hw, c + d * hl - perp * hw, c + d * hl + perp * hw, c - d * hl + perp * hw])
	draw_colored_polygon(PackedVector2Array([poly[0] + Vector2(3, 4), poly[1] + Vector2(3, 4),
			poly[2] + Vector2(3, 4), poly[3] + Vector2(3, 4)]), Color(0, 0, 0, 0.22))
	draw_colored_polygon(poly, Color(0.18, 0.17, 0.20))
	draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(0.08, 0.08, 0.1), 3.0)
	# Chasse-pierres (avant).
	draw_colored_polygon(PackedVector2Array([
		c + d * hl - perp * hw, c + d * (hl + 16.0), c + d * hl + perp * hw]), Color(0.12, 0.11, 0.13))
	# Cheminée + fumée.
	var stack := c + d * (hl * 0.45)
	draw_circle(stack, 7.0, Color(0.10, 0.10, 0.12))
	for i in range(4):
		var pf := float(i) / 4.0
		var sp := stack + d * (12.0 + i * 16.0) + perp * sin(_smoke * 3.0 + i) * 6.0
		draw_circle(sp, 5.0 + i * 3.0, Color(0.5, 0.5, 0.52, 0.30 * (1.0 - pf)))
	# Cabine.
	draw_circle(c - d * (hl * 0.45), 9.0, Color(0.26, 0.24, 0.28))
	for du in [-0.5, 0.5]:
		for su in [-1.0, 1.0]:
			draw_circle(c + d * (hl * du) + perp * (hw + 3.0) * su, 8.0, Color(0.12, 0.09, 0.07))


func _draw_roof_guard(pos: Vector2, face: Vector2) -> void:
	draw_colored_polygon(_diam(pos, 14.0), Color(0, 0, 0, 0.2))
	CharacterArt.draw_person(self, pos + Vector2(0, -6), face, _pal_guard(), false, false, 0.0, 0.0, 0.0)


func _draw_rider(base: Vector2, face: Vector2, mod: Color, pal: Dictionary, hero := false) -> void:
	var bob := sin(_ride + base.x * 0.03) * 2.0
	if hero:
		var back := -_track_dir.normalized() * 16.0
		for i in range(2):
			var pp := base + back + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-2, 5))
			draw_circle(pp, _rng.randf_range(3.0, 5.0), Color(0.7, 0.6, 0.45, 0.22))
	draw_colored_polygon(_diam(base, 20.0), Color(0, 0, 0, 0.2))
	var flip := -1.0 if face.x > 0.1 else 1.0
	_horse_body(base + Vector2(0, bob), flip, mod)
	if _dmg_cd > 0.0 and hero and int(_ride * 20.0) % 2 == 0:
		return
	CharacterArt.draw_person(self, base + Vector2(0, -16 + bob), face, pal, false, false, 0.0, 0.0, 0.0)


func _draw_corpse(pos: Vector2) -> void:
	draw_colored_polygon(_diam(pos, 16.0), Color(0, 0, 0, 0.15))
	draw_circle(pos + Vector2(0, -6), 8.0, Color(0.5, 0.16, 0.14))


func _draw_overlay() -> void:
	var vp := get_viewport_rect().size
	var top := -position / _scale + Vector2(vp.x * 0.5 / _scale, 80.0 / _scale)
	var st := ""
	var col := Color(1, 0.9, 0.6)
	var idx := _nearest_car()
	if _gold_looted and _escaping:
		st = "DISTANCÉ — tu t'enfuis !" if _chase.is_distanced() else "Recule pour décrocher !"
		col = Color(0.6, 1.0, 0.6) if _chase.is_distanced() else Color(1, 0.85, 0.4)
	elif idx >= 0 and absf(_chase.rel.x - float(_cars[idx]["along"])) < 52.0 and absf(_chase.rel.y) < 95.0:
		st = "À HAUTEUR — maintiens E pour piller"
		col = Color(0.6, 1.0, 0.6)
	elif _chase.is_distanced():
		st = "DISTANCÉ — rattrape le train !"
		col = Color(1.0, 0.4, 0.3)
	else:
		st = "Avance/recule pour longer le train (%d/%d wagons)" % [_loot_bags, _cars.size()]
	_text(top, st, int(17.0 / _scale), col)


# --- primitives (copies isolées : systèmes séparés) ---

func _horse_body(base: Vector2, flip: float, mod: Color) -> void:
	var body := Color(0.36, 0.23, 0.13) * mod
	var dark := body.darkened(0.28)
	for dx in [-9.0, -3.0, 4.0, 10.0]:
		draw_line(base + Vector2(dx * flip, -12), base + Vector2((dx + 1.0) * flip, 2), dark, 3.0)
	var bl := base + Vector2(-12 * flip, -16)
	var brr := base + Vector2(12 * flip, -16)
	draw_line(bl, brr, body, 14.0)
	draw_circle(bl, 7.0, body)
	draw_circle(brr, 7.0, body)
	draw_line(brr + Vector2(3 * flip, -3), base + Vector2(18 * flip, 3), dark, 3.0)
	var neck := bl + Vector2(1 * flip, -3)
	var head := bl + Vector2(-11 * flip, -16)
	draw_line(neck, head, body, 7.0)
	draw_circle(head, 4.5, body)
	draw_line(head, head + Vector2(-5 * flip, 2), body, 5.0)


func _pal_guard() -> Dictionary:
	return {
		"hat": Color(0.22, 0.24, 0.30), "hat_band": Color(0.12, 0.13, 0.16),
		"coat": Color(0.26, 0.30, 0.42), "coat_dark": Color(0.17, 0.20, 0.30),
		"shirt": Color(0.40, 0.44, 0.55), "pants": Color(0.20, 0.22, 0.28),
		"skin": Color(0.86, 0.66, 0.48), "bandana": Color(0.55, 0.58, 0.66),
		"belt": Color(0.16, 0.13, 0.10), "buckle": Color(0.80, 0.80, 0.85),
		"boots": Color(0.16, 0.14, 0.12), "hair": Color(0.16, 0.12, 0.08),
	}


func _pal_ally() -> Dictionary:
	return {
		"hat": Color(0.52, 0.46, 0.30), "hat_band": Color(0.30, 0.40, 0.22),
		"coat": Color(0.34, 0.44, 0.26), "coat_dark": Color(0.24, 0.32, 0.18),
		"shirt": Color(0.55, 0.62, 0.38), "pants": Color(0.28, 0.26, 0.20),
		"skin": Color(0.88, 0.67, 0.49), "bandana": Color(0.45, 0.70, 0.40),
		"belt": Color(0.24, 0.16, 0.09), "buckle": Color(0.90, 0.78, 0.34),
		"boots": Color(0.28, 0.18, 0.10), "hair": Color(0.22, 0.15, 0.08),
	}


func _diam(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-r, 0), c + Vector2(0, -r * 0.5),
			c + Vector2(r, 0), c + Vector2(0, r * 0.5)])


func _text(pos: Vector2, s: String, size_px: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var base := pos - Vector2(w * 0.5, 0)
	draw_string(font, base + Vector2(1.5, 1.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(0, 0, 0, 0.7))
	draw_string(font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
