extends Node2D
## stagecoach_chase.gd  (Lot 18)
## Mission DILIGENCE refondue sur la poursuite relative : la diligence roule en
## continu sur la piste ; le joueur à cheval la rattrape (RelativeChaseController),
## se met à hauteur pour la PILLER (maintien E), puis décroche pour s'enfuir.
## L'escorte montée riposte ; l'équipe recrutée (CrewScreen) chevauche et tire.
## Réutilise le HUD, le flux résultat/score et la promotion en bande fidèle.

const COACH_SPEED := 300.0
const BULLET_SPEED := 900.0
const ESCORT_FIRE := 1.8
const ALLY_FIRE := 1.3
const LOOT_TIME := 2.6
const STRONGBOX_VALUE := 900
const FIRE_INTERVAL := 0.22       # tir continu auto-visé (mains libres)
const AUTO_RANGE := 520.0         # portée de verrouillage auto

var _chase := RelativeChaseController.new()
var _horse := HorseController.new()
var _hud: CanvasLayer

var _coach_pos := Vector2.ZERO
var _track_dir := Vector2.RIGHT
var _player_pos := Vector2.ZERO
var _facing := Vector2.RIGHT
var _ride := 0.0
var _cam := Vector2.ZERO
var _scale := 1.6

var _hp := 3
var _max_hp := 3
var _dmg_cd := 0.0
var _fire_cd := 0.0

var _loot_value := 0
var _loot_bags := 0
var _loot_pts: Array[Dictionary] = []   # {off, value, looted, progress, label, gold}
var _elapsed := 0.0
var _over := false
var _escaping := false

# Entités : escorte (ennemis montés) et alliés (équipe). rel = offset / diligence.
var _escort: Array[Dictionary] = []
var _allies: Array[Dictionary] = []
var _bullets: Array[Dictionary] = []
var _corpses: Array[Dictionary] = []
# Juice + immersion (copies isolées, comme le reste du script).
var _shake := 0.0
var _muzzle := 0.0
var _aim_target = null
var _scenery: Array[Dictionary] = []     # décor de bord de piste qui défile
var _dust: Array[Dictionary] = []        # poussière soulevée (vitesse)
var _bursts: Array[Dictionary] = []      # éclats d'impact
var _floaters: Array[Dictionary] = []    # pop-ups +$ / coups
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Iso.top_down = true
	_rng.randomize()
	_horse.mounted = true
	_max_hp = (5 if GameManager.assist else 3) + SaveManager.hp_bonus()
	_max_hp += GameManager.crew_count_role("medic")
	_hp = _max_hp
	_player_pos = _chase.player_world(_coach_pos, _track_dir)
	var vp := get_viewport_rect().size
	_scale = clampf(minf(vp.x, vp.y) / 470.0, 1.2, 2.4)
	scale = Vector2(_scale, _scale)
	_build_loot()
	_spawn_escort()
	_spawn_allies()
	_build_scenery()
	_build_hud()
	AudioManager.play_music("tension")


## Deux butins à piller : le coffre-fort sur le toit + la malle arrière (boot).
func _build_loot() -> void:
	_loot_pts.append({"off": Vector2(0, 0), "value": int(STRONGBOX_VALUE * 0.65),
			"looted": false, "progress": 0.0, "label": "COFFRE-FORT", "gold": true})
	_loot_pts.append({"off": Vector2(-46, 0), "value": int(STRONGBOX_VALUE * 0.4),
			"looted": false, "progress": 0.0, "label": "MALLE", "gold": false})


## Décor de bord de piste (cactus, rochers, buissons, poteaux) — sensation de vitesse.
func _build_scenery() -> void:
	for i in range(16):
		_scenery.append(_new_prop(_rng.randf_range(-400.0, 1500.0)))


func _new_prop(ahead: float) -> Dictionary:
	var kinds := ["cactus", "rock", "bush", "post", "skull"]
	var perp := Vector2(-_track_dir.y, _track_dir.x)
	var side := (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(150.0, 460.0)
	return {"pos": _coach_pos + _track_dir * ahead + perp * side,
			"kind": kinds[_rng.randi() % kinds.size()], "s": _rng.randf_range(0.8, 1.4)}


func _build_hud() -> void:
	_hud = preload("res://scenes/HUD.tscn").instantiate()
	add_child(_hud)
	_hud.set_health(_hp, _max_hp)
	_hud.set_loot(0, 0)
	_hud.set_money(SaveManager.total_money)
	_hud.set_alarm(0.0)
	_hud.set_objective("Rattrape la DILIGENCE et PILLE-la (maintiens E à hauteur)")
	if not _allies.is_empty():
		_hud.show_toast("ÉQUIPE EN SELLE ! (%d)" % _allies.size())


func _spawn_escort() -> void:
	# Gardes montés qui FONCENT sur le joueur puis décrochent (+1 par notoriété).
	var n := 3 + clampi(SaveManager.notoriety / 2, 0, 3)
	for i in range(n):
		var home := Vector2(-30.0 - 30.0 * (i % 2), (-80.0 if i % 2 == 0 else 80.0) - 22.0 * (i / 2))
		_escort.append({
			"rel": home, "home": home, "hp": 2, "fire_cd": _rng.randf_range(0.5, ESCORT_FIRE),
			"alive": true, "facing": Vector2.LEFT, "charge_t": _rng.randf_range(1.0, 3.0), "charging": false})
	# Messager au fusil (shotgun) assis à côté du cocher : tire fort à courte portée.
	_escort.append({"rel": Vector2(46, -10), "home": Vector2(46, -10), "hp": 3,
			"fire_cd": 1.2, "alive": true, "facing": Vector2.LEFT, "charge_t": 99.0,
			"charging": false, "messenger": true})


func _spawn_allies() -> void:
	for c in GameManager.crew:
		var role := str(c.get("role", ""))
		if role == "gunman" or role == "marksman":
			_allies.append({"off": Vector2(_rng.randf_range(-70, -20), _rng.randf_range(-80, 80)),
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
	_dmg_cd = maxf(0.0, _dmg_cd - delta)
	# Diligence : avance continue avec un cap qui ondule (piste sinueuse).
	_track_dir = Vector2.RIGHT.rotated(sin(_coach_pos.x * 0.0007) * 0.16)
	_coach_pos += _track_dir * COACH_SPEED * delta
	# Joueur : déplacement relatif depuis l'entrée (alignée écran).
	var input := InputManager.get_move_vector()
	_chase.update(delta, input)
	var np := _chase.player_world(_coach_pos, _track_dir)
	var mv := np - _player_pos
	if mv.length() > 1.0:
		_facing = mv.normalized()
	_player_pos = np
	_ride += delta * 14.0
	_update_scenery(delta)
	_update_particles(delta)
	_update_loot(delta)
	_update_escort_motion(delta)
	_update_combat(delta)
	_advance_bullets(delta)
	_update_camera(delta)
	_check_end()
	if _hud != null:
		_hud.set_health(_hp, _max_hp)
		_hud.set_loot(_loot_bags, _loot_value)
	queue_redraw()


## Recycle le décor passé derrière la diligence vers l'avant (défilement infini).
func _update_scenery(delta: float) -> void:
	for p in _scenery:
		var along := (p["pos"] as Vector2 - _coach_pos).dot(_track_dir)
		if along < -650.0:
			var np := _new_prop(_rng.randf_range(900.0, 1500.0))
			p["pos"] = np["pos"]
			p["kind"] = np["kind"]
			p["s"] = np["s"]
	# Poussière soulevée par l'attelage et par le héros (vitesse).
	if _rng.randf() < 0.6:
		_dust.append({"pos": _coach_pos - _track_dir * 50.0 + Vector2(0, 6), "t": 0.0,
				"r": _rng.randf_range(4, 8), "vel": -_track_dir * 40.0})
	if _rng.randf() < 0.5:
		_dust.append({"pos": _player_pos - _track_dir * 16.0, "t": 0.0,
				"r": _rng.randf_range(3, 6), "vel": -_track_dir * 30.0})


## Particules (poussière, éclats, pop-ups) + amortissement du tremblement.
func _update_particles(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 24.0)
	_muzzle = maxf(0.0, _muzzle - delta)
	var d2: Array[Dictionary] = []
	for p in _dust:
		p["t"] = float(p["t"]) + delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		if float(p["t"]) < 0.7:
			d2.append(p)
	_dust = d2
	var b2: Array[Dictionary] = []
	for p in _bursts:
		p["t"] = float(p["t"]) + delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		p["vel"] = (p["vel"] as Vector2) * 0.9
		if float(p["t"]) < 0.55:
			b2.append(p)
	_bursts = b2
	var f2: Array[Dictionary] = []
	for f in _floaters:
		f["t"] = float(f["t"]) + delta
		f["pos"] = (f["pos"] as Vector2) + Vector2(0, -26.0 * delta)
		if float(f["t"]) < 1.1:
			f2.append(f)
	_floaters = f2


## Escorte : alterne CHARGE vers le joueur et repli vers sa position d'origine.
func _update_escort_motion(delta: float) -> void:
	for e in _escort:
		if not e["alive"] or e.get("messenger", false):
			continue
		e["charge_t"] = float(e["charge_t"]) - delta
		if float(e["charge_t"]) <= 0.0:
			e["charging"] = not bool(e["charging"])
			e["charge_t"] = _rng.randf_range(1.4, 2.6)
		var tgt: Vector2 = (_chase.rel + Vector2(26, 0)) if bool(e["charging"]) else (e["home"] as Vector2)
		e["rel"] = (e["rel"] as Vector2).lerp(tgt, clampf(delta * 1.7, 0.0, 1.0))


# --- Pillage ---

func _nearest_loot() -> int:
	var best := 1.0e20
	var idx := -1
	for i in range(_loot_pts.size()):
		if _loot_pts[i]["looted"]:
			continue
		var d := absf(_chase.rel.x - float((_loot_pts[i]["off"] as Vector2).x))
		if d < best:
			best = d
			idx = i
	return idx


func _update_loot(delta: float) -> void:
	var idx := _nearest_loot()
	if idx < 0:
		return
	var pt: Dictionary = _loot_pts[idx]
	var alongside := absf(_chase.rel.x - float((pt["off"] as Vector2).x)) < 58.0
	var side_ok := absf(_chase.rel.y) < 95.0
	if alongside and side_ok and InputManager.is_interact_held():
		pt["progress"] = minf(1.0, float(pt["progress"]) + delta / LOOT_TIME)
		if float(pt["progress"]) >= 1.0:
			_loot_point(idx)


func _loot_point(idx: int) -> void:
	var pt: Dictionary = _loot_pts[idx]
	pt["looted"] = true
	var val := int(int(pt["value"]) * SaveManager.loot_mult())
	_loot_value += val
	_loot_bags += 1
	AudioManager.play("safe")
	_shake = maxf(_shake, 6.0)
	_floaters.append({"pos": _coach_pos + _rot(pt["off"]), "t": 0.0, "text": "+%d $" % val, "col": Color(1, 0.9, 0.4)})
	# La fuite s'ouvre dès que le coffre-fort (or) est pris ; la malle est un bonus.
	if bool(pt["gold"]):
		_escaping = true
		if _hud != null:
			_hud.show_toast("COFFRE-FORT PILLÉ ! +%d $" % val)
			_hud.set_objective("DÉCROCHE ! Recule pour t'enfuir (malle = bonus)")
	elif _hud != null:
		_hud.show_toast("Malle pillée ! +%d $" % val)


func _all_looted() -> bool:
	for pt in _loot_pts:
		if not pt["looted"]:
			return false
	return true


# --- Combat ---

func _update_combat(delta: float) -> void:
	# Escorte : tire sur le joueur quand il est proche.
	for e in _escort:
		if not e["alive"]:
			continue
		var ep: Vector2 = _coach_pos + _rot(e["rel"])
		e["facing"] = (_player_pos - ep).normalized()
		e["fire_cd"] = float(e["fire_cd"]) - delta
		if e["fire_cd"] <= 0.0 and ep.distance_to(_player_pos) < 380.0:
			_spawn_bullet(ep, (_player_pos - ep), false)
			e["fire_cd"] = ESCORT_FIRE * (1.4 if GameManager.assist else 1.0)
	# Alliés : chevauchent près du joueur et tirent sur l'escorte la plus proche.
	for a in _allies:
		if not a["alive"]:
			continue
		var ap: Vector2 = _player_pos + _rot(a["off"])
		a["fire_cd"] = float(a["fire_cd"]) - delta
		var tgt = _nearest_escort(ap)
		if tgt != null:
			a["facing"] = (tgt - ap).normalized()
			if a["fire_cd"] <= 0.0:
				_spawn_bullet(ap, (tgt - ap), true)
				a["fire_cd"] = ALLY_FIRE
	# Tir du joueur : AUTO-VISÉE sur l'escorte la plus proche + TIR CONTINU.
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_aim_target = _nearest_escort(_player_pos)
	var locked: bool = _aim_target != null and _player_pos.distance_to(_aim_target) < AUTO_RANGE
	var manual := InputManager.is_fire_pressed()
	if _fire_cd <= 0.0 and (locked or manual):
		var dir: Vector2 = (_aim_target - _player_pos) if locked else _track_dir
		if dir.length() < 1.0:
			dir = _track_dir
		_facing = dir.normalized()
		_spawn_bullet(_player_pos + dir.normalized() * 18.0, dir, true)
		_fire_cd = FIRE_INTERVAL * SaveManager.firerate_mult()
		_muzzle = 0.06
		AudioManager.play("shot", -6.0)


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
			for e in _escort:
				if e["alive"] and (_coach_pos + _rot(e["rel"])).distance_to(b["pos"]) < 16.0:
					e["hp"] = int(e["hp"]) - 1
					hit = true
					_spawn_burst(b["pos"], Color(0.8, 0.2, 0.15))
					if int(e["hp"]) <= 0:
						e["alive"] = false
						_corpses.append({"pos": _coach_pos + _rot(e["rel"]), "t": 0.0})
						_kill_reward(_coach_pos + _rot(e["rel"]))
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
	_shake = maxf(_shake, 9.0)
	AudioManager.play("hit_player", -4.0)
	if _hud != null and _hp > 0:
		_hud.flash(Color(1, 0, 0, 0.35))


func _spawn_burst(at: Vector2, col: Color) -> void:
	for i in range(8):
		_bursts.append({"pos": at, "t": 0.0, "col": col if i % 2 == 0 else Color(0.5, 0.35, 0.2),
				"vel": Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(50, 170)})


## Une escorte tombée lâche une petite bourse (récompense + juice).
func _kill_reward(at: Vector2) -> void:
	_shake = maxf(_shake, 7.0)
	var bounty := 90 + SaveManager.notoriety * 10
	SaveManager.refund(bounty)
	AudioManager.play("hit_guard")
	_floaters.append({"pos": at, "t": 0.0, "text": "+%d $" % bounty, "col": Color(1, 0.85, 0.5)})


func _nearest_escort(from: Vector2):
	var best := 1.0e20
	var pos = null
	for e in _escort:
		if not e["alive"]:
			continue
		var ep: Vector2 = _coach_pos + _rot(e["rel"])
		var d := from.distance_to(ep)
		if d < best:
			best = d
			pos = ep
	return pos


# --- Fin de mission ---

func _check_end() -> void:
	if _over:
		return
	if _hp <= 0:
		_end(false)
		return
	# Évasion réussie : diligence pillée + on a décroché loin derrière.
	if _escaping and _chase.is_distanced():
		_end(true)


func _end(success: bool) -> void:
	_over = true
	if success:
		_promote_crew_to_gang()
		if _hud != null:
			_hud.show_toast("FUITE RÉUSSIE !")
	else:
		if _hud != null:
			_hud.show_toast("ABATTU ! ÉCHEC")
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
	for e in _escort:
		if not e["alive"]:
			kills += 1
	var time_bonus: int = maxi(0, int(round((120.0 - _elapsed) * 2.0)))
	var crew := 200 * GameManager.crew_count_role("scout") + 120 * _live_allies()
	var escort_bonus := 80 * kills
	return {
		"loot": _loot_value, "stealth": 0, "time": time_bonus,
		"contract": escort_bonus, "crew": crew,
		"total": _loot_value + time_bonus + crew + escort_bonus,
	}


func _live_allies() -> int:
	var n := 0
	for a in _allies:
		if a["alive"]:
			n += 1
	return n


# --- Rendu ---

func _rot(off: Vector2) -> Vector2:
	# Offset exprimé dans le repère de la course (x avant, y latéral) -> monde.
	var d := _track_dir.normalized()
	var perp := Vector2(-d.y, d.x)
	return d * off.x + perp * off.y


func _update_camera(delta: float) -> void:
	var vp := get_viewport_rect().size
	var focus := _player_pos.lerp(_coach_pos, 0.4)
	_cam = _cam.lerp(vp * 0.5 - focus * _scale, clampf(delta * 8.0, 0.0, 1.0))
	var sh := Vector2.ZERO
	if _shake > 0.1:
		sh = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake
	position = _cam + sh


func _draw() -> void:
	_draw_ground()
	_draw_lane()
	for du in _dust:
		var a: float = clampf(1.0 - float(du["t"]) / 0.7, 0.0, 1.0)
		draw_circle(du["pos"], float(du["r"]) * (0.6 + a), Color(0.72, 0.6, 0.42, a * 0.5))
	# Tri de profondeur simple par Y monde (décor inclus).
	var items: Array[Dictionary] = []
	for p in _scenery:
		items.append({"y": (p["pos"] as Vector2).y, "k": "prop", "o": p})
	items.append({"y": _coach_pos.y, "k": "coach"})
	for e in _escort:
		if e["alive"]:
			var ep: Vector2 = _coach_pos + _rot(e["rel"])
			items.append({"y": ep.y, "k": "escort", "p": ep, "f": e["facing"]})
	for a in _allies:
		if a["alive"]:
			var ap: Vector2 = _player_pos + _rot(a["off"])
			items.append({"y": ap.y, "k": "ally", "p": ap, "f": a["facing"]})
	for c in _corpses:
		items.append({"y": c["pos"].y - 1.0, "k": "corpse", "p": c["pos"]})
	items.append({"y": _player_pos.y, "k": "me"})
	items.sort_custom(func(a, b): return a["y"] < b["y"])
	for it in items:
		match it["k"]:
			"prop": _draw_prop(it["o"])
			"coach": _draw_coach()
			"escort": _draw_rider(it["p"], it["f"], Color(0.7, 0.78, 1.05), _pal_escort())
			"ally": _draw_rider(it["p"], it["f"], Color(0.78, 1.05, 0.8), _pal_ally())
			"corpse": _draw_corpse(it["p"])
			"me": _draw_rider(_player_pos, _facing, Color(1.0, 0.92, 0.7), CharacterArt.hero_palette(), true)
	# Flash de bouche au canon du héros.
	if _muzzle > 0.0:
		draw_circle(_player_pos + _facing * 20.0 + Vector2(0, -14), 7.0 * (_muzzle / 0.06), Color(1, 0.92, 0.5, 0.9))
	for b in _bullets:
		var p: Vector2 = b["pos"]
		var d: Vector2 = (b["vel"] as Vector2).normalized()
		var col := Color(1, 0.9, 0.4) if b["friendly"] else Color(1, 0.5, 0.25)
		draw_line(p - d * 15.0, p, Color(col.r, col.g, col.b, 0.5), 3.0)
		draw_circle(p, 3.0, col)
	for bu in _bursts:
		var ba: float = clampf(1.0 - float(bu["t"]) / 0.55, 0.0, 1.0)
		var bc: Color = bu["col"]
		draw_circle(bu["pos"], 2.0 + ba * 2.0, Color(bc.r, bc.g, bc.b, ba))
	for f in _floaters:
		var fa: float = clampf(1.0 - float(f["t"]) / 1.1, 0.0, 1.0)
		var fc: Color = f["col"]
		_text(f["pos"] + Vector2(0, -34), str(f["text"]), 15, Color(fc.r, fc.g, fc.b, fa))
	_draw_overlay()


## Décor de bord de piste.
func _draw_prop(p: Dictionary) -> void:
	var c: Vector2 = p["pos"]
	var s: float = p["s"]
	draw_colored_polygon(_diam(c, 12.0 * s), Color(0, 0, 0, 0.16))
	match p["kind"]:
		"cactus":
			draw_line(c, c + Vector2(0, -34 * s), Color(0.27, 0.45, 0.24), 7.0 * s)
			draw_line(c + Vector2(0, -16 * s), c + Vector2(-11 * s, -22 * s), Color(0.27, 0.45, 0.24), 5.0 * s)
			draw_line(c + Vector2(0, -24 * s), c + Vector2(10 * s, -30 * s), Color(0.27, 0.45, 0.24), 5.0 * s)
		"rock":
			draw_circle(c + Vector2(0, -7 * s), 11.0 * s, Color(0.5, 0.47, 0.43))
			draw_circle(c + Vector2(-6 * s, -4 * s), 7.0 * s, Color(0.42, 0.39, 0.36))
		"bush":
			draw_circle(c + Vector2(0, -6 * s), 9.0 * s, Color(0.36, 0.42, 0.22))
			draw_circle(c + Vector2(7 * s, -4 * s), 6.0 * s, Color(0.32, 0.38, 0.20))
		"post":
			draw_line(c, c + Vector2(0, -40 * s), Color(0.36, 0.25, 0.14), 4.0 * s)
			draw_line(c + Vector2(-9 * s, -32 * s), c + Vector2(9 * s, -32 * s), Color(0.30, 0.21, 0.12), 3.0 * s)
		"skull":
			draw_circle(c + Vector2(0, -6 * s), 7.0 * s, Color(0.88, 0.85, 0.78))
			draw_line(c + Vector2(0, -6 * s), c + Vector2(0, 2 * s), Color(0.8, 0.77, 0.7), 3.0 * s)


func _draw_ground() -> void:
	var perp := Vector2(-_track_dir.y, _track_dir.x)
	var step := 120.0
	var base := floorf(_coach_pos.x / step) * step
	for i in range(-7, 15):
		var x := base + i * step
		var c := Color(0.78, 0.62, 0.42) if int(roundf(x / step)) % 2 == 0 else Color(0.73, 0.57, 0.38)
		var center := Vector2(x, _coach_pos.y)
		var a := center + perp * 1000.0 - _track_dir * (step * 0.5)
		var bb := center - perp * 1000.0 - _track_dir * (step * 0.5)
		var cc := center - perp * 1000.0 + _track_dir * (step * 0.5)
		var dd := center + perp * 1000.0 + _track_dir * (step * 0.5)
		draw_colored_polygon(PackedVector2Array([a, dd, cc, bb]), c)


func _draw_lane() -> void:
	var perp := Vector2(-_track_dir.y, _track_dir.x)
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for k in range(-4, 12):
			var along := _coach_pos + _track_dir * (k * 80.0 - 200.0)
			pts.append(along + perp * (side * RelativeChaseController.LANE_HALF))
		draw_polyline(pts, Color(0.95, 0.85, 0.3, 0.3), 2.0)


func _draw_coach() -> void:
	var d := _track_dir.normalized()
	var perp := Vector2(-d.y, d.x)
	var c := _coach_pos
	# Chevaux d'attelage devant.
	for s in [-12.0, 12.0]:
		var hp: Vector2 = c + d * 78.0 + perp * float(s)
		draw_colored_polygon(_diam(hp, 13.0), Color(0, 0, 0, 0.16))
		draw_circle(hp, 7.0, Color(0.32, 0.2, 0.12))
	# Ombre + caisse.
	var hl := 56.0
	var hw := 30.0
	var poly := PackedVector2Array([
		c - d * hl - perp * hw, c + d * hl - perp * hw, c + d * hl + perp * hw, c - d * hl + perp * hw])
	draw_colored_polygon(PackedVector2Array([poly[0] + Vector2(3, 4), poly[1] + Vector2(3, 4),
			poly[2] + Vector2(3, 4), poly[3] + Vector2(3, 4)]), Color(0, 0, 0, 0.2))
	draw_colored_polygon(poly, Color(0.46, 0.31, 0.18))
	draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(0.22, 0.14, 0.08), 3.0)
	# Toit + roues.
	draw_colored_polygon(PackedVector2Array([
		c - d * (hl - 10) - perp * (hw - 8), c + d * (hl - 24) - perp * (hw - 8),
		c + d * (hl - 24) + perp * (hw - 8), c - d * (hl - 10) + perp * (hw - 8)]), Color(0.40, 0.26, 0.15))
	for su in [-1.0, 1.0]:
		for du in [-0.5, 0.5]:
			draw_circle(c + d * (hl * du) + perp * (hw + 4) * su, 9.0, Color(0.16, 0.11, 0.07))
			draw_circle(c + d * (hl * du) + perp * (hw + 4) * su, 4.0, Color(0.45, 0.32, 0.18))
	# Cocher + messager au fusil sur le banc avant.
	draw_circle(c + d * 40.0 + perp * 9.0, 5.0, Color(0.25, 0.17, 0.10))
	# Butins (coffre-fort + malle) : pastille + jauge de pillage chacun.
	for pt in _loot_pts:
		var pc: Vector2 = c + _rot(pt["off"])
		var looted: bool = pt["looted"]
		var base := Color(0.92, 0.78, 0.32) if bool(pt["gold"]) else Color(0.6, 0.45, 0.28)
		draw_circle(pc, 11.0 if bool(pt["gold"]) else 9.0, base if not looted else Color(0.5, 0.42, 0.25))
		if float(pt["progress"]) > 0.0 and not looted:
			var bw := 52.0
			var head := pc + Vector2(0, -hw - 16.0)
			draw_rect(Rect2(head + Vector2(-bw * 0.5, -4), Vector2(bw, 6)), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(head + Vector2(-bw * 0.5, -4), Vector2(bw * float(pt["progress"]), 6)), Color(0.95, 0.8, 0.2))
		if not looted:
			_text(pc + Vector2(0, -hw - 24.0), str(pt["label"]), 12, Color(1, 0.95, 0.7))


func _draw_rider(base: Vector2, face: Vector2, mod: Color, pal: Dictionary, hero := false) -> void:
	var bob := sin(_ride + base.x * 0.03) * 2.0
	var back := -_track_dir.normalized() * 16.0
	if hero:
		for i in range(2):
			var pp := base + back + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-2, 5))
			draw_circle(pp, _rng.randf_range(3.0, 5.0), Color(0.7, 0.6, 0.45, 0.22))
	draw_colored_polygon(_diam(base, 20.0), Color(0, 0, 0, 0.2))
	var flip := -1.0 if face.x > 0.1 else 1.0
	_horse_body(base + Vector2(0, bob), flip, mod)
	if _dmg_cd > 0.0 and hero and int(_ride * 20.0) % 2 == 0:
		return  # clignotement d'invuln
	CharacterArt.draw_person(self, base + Vector2(0, -16 + bob), face, pal, false, false, 0.0, 0.0, 0.0)


## Palettes des cavaliers (escorte = lois en manteau sombre ; allié = hors-la-loi).
func _pal_escort() -> Dictionary:
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


func _draw_corpse(pos: Vector2) -> void:
	draw_colored_polygon(_diam(pos, 18.0), Color(0, 0, 0, 0.15))
	draw_circle(pos + Vector2(0, -6), 8.0, Color(0.5, 0.16, 0.14))


func _draw_overlay() -> void:
	var vp := get_viewport_rect().size
	var top := -position / _scale + Vector2(vp.x * 0.5 / _scale, 80.0 / _scale)
	var st := ""
	var col := Color(1, 0.9, 0.6)
	var idx := _nearest_loot()
	var at_loot := idx >= 0 and absf(_chase.rel.x - float((_loot_pts[idx]["off"] as Vector2).x)) < 58.0 and absf(_chase.rel.y) < 95.0
	if _escaping and not at_loot:
		st = "DISTANCÉ — tu t'enfuis !" if _chase.is_distanced() else "Recule pour décrocher ! (malle = bonus)"
		col = Color(0.6, 1.0, 0.6) if _chase.is_distanced() else Color(1, 0.85, 0.4)
	elif at_loot:
		st = "À HAUTEUR — maintiens E pour piller %s" % str(_loot_pts[idx]["label"])
		col = Color(0.6, 1.0, 0.6)
	elif _chase.is_distanced():
		st = "DISTANCÉ — rattrape la diligence !"
		col = Color(1.0, 0.4, 0.3)
	else:
		st = "Longe la diligence — PILLE (E) — tir auto"
	_text(top, st, int(18.0 / _scale), col)


# --- primitives ---

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


func _diam(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-r, 0), c + Vector2(0, -r * 0.5),
			c + Vector2(r, 0), c + Vector2(0, r * 0.5)])


func _text(pos: Vector2, s: String, size_px: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var base := pos - Vector2(w * 0.5, 0)
	draw_string(font, base + Vector2(1.5, 1.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(0, 0, 0, 0.7))
	draw_string(font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)
