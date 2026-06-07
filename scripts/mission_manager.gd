extends Node2D
## mission_manager.gd
## Racine de la mission. Construit le niveau (murs, comptoirs), instancie le
## joueur, les gardes, le coffre, les sacs et la sortie, câble les signaux et
## décide de la réussite / échec, puis transmet le résultat au GameManager.

const PlayerScene := preload("res://scenes/Player.tscn")
const GuardScene := preload("res://scenes/Guard.tscn")
const SafeScene := preload("res://scenes/Safe.tscn")
const LootBagScene := preload("res://scenes/LootBag.tscn")
const ExitZoneScene := preload("res://scenes/ExitZone.tscn")

const LEVEL_COUNT := 3
const CONFIG_DIR := "res://data/"

# Fichier de niveau : data/mission_0N.json selon GameManager.current_level.
# Géométrie pilotée par les données (floor / walls / props / loot / guards).
# DEFAULT_CFG est un filet de sécurité minimal mais JOUABLE si un fichier manque.
const DEFAULT_CFG := {
	"name": "Banque (secours)",
	"floor": [20, 20, 820, 560],
	"walls": [
		[0, 0, 860, 20, 1], [0, 580, 860, 20, 1], [840, 0, 20, 600, 1],
		[0, 0, 20, 240, 1], [0, 340, 20, 260, 1],
		[560, 20, 20, 180], [560, 300, 20, 160], [580, 200, 100, 20],
	],
	"props": [["vault", 580, 150], ["counter", 300, 300], ["barrel", 70, 520]],
	"player_start": [400, 500],
	"exit": [70, 300],
	"safe": {"pos": [650, 120], "value": 500, "open_time": 2.5},
	"loot": [{"pos": [650, 190], "value": 250}, {"pos": [300, 460], "value": 150}],
	"guards": [{"route": [[150, 250], [760, 250], [760, 230], [150, 230]]}],
}

var _cfg: Dictionary = {}

@onready var world: Node2D = $World
@onready var hud: CanvasLayer = $HUD

var player: CharacterBody2D
var alarm: Node
var _guards: Array = []
var _exit: Area2D
var _safe: Area2D
var _walls: Array[Dictionary] = []
var _floor_rect: Rect2
var _loot_nodes: Array = []
var _renderer: Node2D
var _bullets: Node
var _fx: Node2D

var _mission_over := false
var _safe_open := false
var _loot_bags := 0
var _loot_value := 0

# Suivi pour le score et la tension.
var _elapsed := 0.0
var _alarm_triggered := false
var _alarm_peak := 0.0
var _was_engaged := false
var _foot_t := 0.0
var _reinforced := false
var _contract: Dictionary = {}
var _guards_killed := 0
var _loot_total := 0
var _dynamite: Area2D = null
var _dyn_used := false
var _hostages: Array = []
var _hostages_freed := 0
var _safes2: Array = []
var _allies: Array = []
var _coach_group: Array = []
var _coach_center := Vector2.ZERO
var _coach_stopped := false
const COACH_SPEED := 52.0
const COACH_END_X := 1950.0
var _focus := 1.0
var _focus_active := false
const FOCUS_SLOW := 0.35
const FOCUS_DRAIN := 0.33
const FOCUS_RECHARGE := 0.13


func _ready() -> void:
	randomize()
	Engine.time_scale = 1.0
	_cfg = _load_config()
	_apply_crew_to_cfg()
	_build_alarm()
	_build_floor()
	_build_walls()
	_spawn_prop_solids()
	_spawn_player()
	_spawn_loot()
	_spawn_safe()
	_spawn_exit()
	_spawn_guards()
	_build_bullets()
	_spawn_strongboxes()
	_spawn_hostages()
	_spawn_dynamite()
	_build_iso_renderer()
	_spawn_crew()
	_init_coach_group()
	_build_effects()
	_connect_hud()
	_update_objective()
	# Annonce le braquage en cours (nom + difficulté du niveau).
	if hud.has_method("show_toast"):
		var diff := str(_cfg.get("difficulty", ""))
		var lbl := str(_cfg.get("name", "Braquage"))
		hud.show_toast("%s%s" % [lbl, (" — " + diff) if diff != "" else ""])
	_pick_contract()
	_update_objective()
	AudioManager.play_music("tension")


## Contrat (défi) de la banque : déterministe sur les banques procédurales.
func _pick_contract() -> void:
	var defs := [
		{"id": "ghost", "desc": "FANTÔME : aucune alarme générale", "bonus": 400},
		{"id": "flash", "desc": "ÉCLAIR : sortir en moins de 75 s", "bonus": 350},
		{"id": "sweep", "desc": "RAFLE : rafler TOUT le butin", "bonus": 300},
		{"id": "pacifist", "desc": "PACIFISTE : aucun garde abattu", "bonus": 300},
	]
	var i := (absi(GameManager.mission_seed) % defs.size()) if GameManager.procedural else (randi() % defs.size())
	_contract = defs[i]
	if hud.has_method("show_toast"):
		hud.show_toast("CONTRAT — %s (+%d $)" % [str(_contract["desc"]), int(_contract["bonus"])])


func _contract_done() -> bool:
	match str(_contract.get("id", "")):
		"ghost": return not _alarm_triggered
		"flash": return _elapsed <= 75.0
		"sweep": return _loot_total > 0 and _loot_bags >= _loot_total
		"pacifist": return _guards_killed == 0
	return false


## Le "convoi" (diligence + coffres latéraux + snipers à bord + butin proche)
## se déplace d'un bloc : on mémorise chaque membre et son décalage au centre.
func _init_coach_group() -> void:
	if not GameManager.coach_mission or not is_instance_valid(_safe):
		return
	_coach_center = _safe.global_position
	_coach_group.append({"node": _safe, "off": Vector2.ZERO})
	for sb in _safes2:
		if is_instance_valid(sb):
			_coach_group.append({"node": sb, "off": sb.global_position - _coach_center})
	for g in _guards:
		if ("kind" in g) and g.kind == "sniper":
			_coach_group.append({"node": g, "off": g.global_position - _coach_center})
	for b in _loot_nodes:
		if is_instance_valid(b) and b.global_position.distance_to(_coach_center) < 260.0:
			_coach_group.append({"node": b, "off": b.global_position - _coach_center})
	for h in _hostages:
		if is_instance_valid(h) and h.global_position.distance_to(_coach_center) < 260.0:
			_coach_group.append({"node": h, "off": h.global_position - _coach_center})


## La diligence roule : il faut la rattraper et la piller en mouvement.
func _move_coach(delta: float) -> void:
	if not GameManager.coach_mission or _mission_over or _coach_stopped:
		return
	if is_instance_valid(_safe) and _safe._is_open:
		_coach_stopped = true
		if hud.has_method("show_toast"):
			hud.show_toast("DILIGENCE STOPPÉE !")
		return
	if _coach_center.x >= COACH_END_X:
		_coach_stopped = true
		if hud.has_method("show_toast"):
			hud.show_toast("La diligence se traîne... rattrape-la !")
		return
	_coach_center.x += COACH_SPEED * delta
	for m in _coach_group:
		var nd = m["node"]
		if is_instance_valid(nd):
			nd.global_position = _coach_center + m["off"]


## Atouts d'équipe modifiant la config (artificier -> dynamite sur la diligence).
func _apply_crew_to_cfg() -> void:
	if not GameManager.coach_mission:
		return
	if GameManager.crew_count_role("demolisher") > 0:
		var sp: Array = _cfg.get("safe", {}).get("pos", [1140, 560])
		_cfg["dynamite"] = [float(sp[0]) - 90.0, float(sp[1]) + 30.0]


## Équipe recrutée (attaque de diligence) : alliés combattants + bonus.
func _spawn_crew() -> void:
	if not GameManager.coach_mission:
		return
	var medics := GameManager.crew_count_role("medic")
	if medics > 0 and player != null:
		player.max_hp += medics
		player.hp = player.max_hp
	for c in GameManager.crew:
		var role := str(c.get("role", ""))
		if role == "gunman" or role == "marksman":
			var a := preload("res://scripts/ally_ai.gd").new()
			a.player = player
			a.guards = _guards
			a.bullet_system = _bullets
			a.marksman = (role == "marksman")
			a.collision_layer = 0
			a.collision_mask = 1
			var cs := CollisionShape2D.new()
			var circ := CircleShape2D.new()
			circ.radius = 12.0
			cs.shape = circ
			a.add_child(cs)
			a.set_meta("cname", str(c.get("name", "")))
			a.set_meta("crole", role)
			a.global_position = player.global_position + Vector2(randf_range(-70, 70), randf_range(-40, 80))
			world.add_child(a)
			_allies.append(a)
	if _renderer != null:
		_renderer.allies = _allies
	if _bullets != null:
		_bullets.allies = _allies
		_bullets.ally_down.connect(_on_ally_down)
	if hud.has_method("show_toast") and not _allies.is_empty():
		hud.show_toast("ÉQUIPE EN POSITION ! (%d alliés)" % _allies.size())


func _on_ally_down(a: Node) -> void:
	if is_instance_valid(a):
		if _renderer != null and _renderer.has_method("add_corpse"):
			_renderer.add_corpse(a.global_position, a.get_facing())
		_allies.erase(a)
		if _renderer != null:
			_renderer.allies = _allies
		a.queue_free()
	if _fx != null:
		_fx.add_shake(3.0)
	AudioManager.play("hit_player", -3.0)
	if hud.has_method("show_toast"):
		hud.show_toast("ALLIÉ À TERRE !")


func _build_bullets() -> void:
	_bullets = preload("res://scripts/bullet_system.gd").new()
	_bullets.name = "BulletSystem"
	_bullets.player = player
	_bullets.guards = _guards
	add_child(_bullets)
	_bullets.guard_killed.connect(_on_guard_killed)
	_bullets.guard_hit.connect(_on_guard_hit)
	_bullets.player_hit.connect(_on_player_hit)
	player.bullet_system = _bullets
	player.health_changed.connect(_on_player_health)
	player.ammo_changed.connect(_on_player_ammo)
	for g in _guards:
		g.bullet_system = _bullets


## Recalcule le zoom de caméra quand l'écran change de taille (navigateur/mobile).
func _on_viewport_resized() -> void:
	if is_instance_valid(_renderer) and _renderer.has_method("refit"):
		_renderer.refit()


func _build_effects() -> void:
	_fx = preload("res://scripts/effects.gd").new()
	_fx.name = "Effects"
	# Enfant du renderer : hérite du zoom/position de la caméra, donc les
	# particules restent toujours alignées sur les entités (et suivent le shake).
	_fx.iso_offset = Vector2.ZERO
	_renderer.add_child(_fx)
	_renderer.fx = _fx
	# Branche les effets sur les évènements de combat.
	_bullets.impact.connect(func(pos, dir, friendly): _fx.impact_spark(pos, dir, friendly))
	_bullets.wall_impact.connect(func(pos): _fx.wall_puff(pos))
	player.fired.connect(func(pos, dir):
		_fx.muzzle_flash(pos, dir)
		_fx.add_shake(3.0)
		AudioManager.play("shot"))
	player.damaged.connect(func():
		if hud.has_method("flash"):
			hud.flash(Color(0.8, 0.0, 0.0, 0.45))
		_fx.add_shake(7.0)
		AudioManager.play("hit_player"))


func _build_iso_renderer() -> void:
	_renderer = preload("res://scripts/iso_renderer.gd").new()
	_renderer.name = "IsoRenderer"
	_renderer.floor_rect = _floor_rect
	_renderer.walls = _walls
	_renderer.props = _cfg.get("props", [])
	_renderer.biome = str(_cfg.get("biome", "desert"))
	_renderer.dynamite = _dynamite
	_renderer.hostages = _hostages
	_renderer.coach_mode = GameManager.coach_mission
	_renderer.safes2 = _safes2
	_renderer.player = player
	_renderer.guards = _guards
	_renderer.loot = _loot_nodes
	_renderer.safe = _safe
	_renderer.exit_zone = _exit
	_renderer.bullets = _bullets
	add_child(_renderer)
	_renderer.setup()
	# Recalcule le zoom si la fenêtre/écran change de taille (navigateur, mobile).
	get_viewport().size_changed.connect(_on_viewport_resized)
	# Le joueur vise vers le clic : il a besoin du renderer pour convertir
	# la position écran/souris en point monde cartésien.
	player.iso_renderer = _renderer


# --- Données de mission ---

func _config_path() -> String:
	var lvl: int = clampi(GameManager.current_level, 1, LEVEL_COUNT)
	return "%smission_%02d.json" % [CONFIG_DIR, lvl]

## Charge le niveau courant. Retombe sur DEFAULT_CFG si absent/invalide.
func _load_config() -> Dictionary:
	# Banque PROCÉDURALE propre à la ville (depuis la carte du monde).
	if GameManager.procedural:
		var tier := clampi(GameManager.current_level, 1, 3)
		var tname := str(GameManager.current_town_def().get("name", "Banque"))
		return _generate_bank_cfg(GameManager.mission_seed, tier, GameManager.mission_biome, tname)
	var path := "res://data/coach.json" if GameManager.coach_mission else _config_path()
	if not FileAccess.file_exists(path):
		return DEFAULT_CFG.duplicate(true)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return DEFAULT_CFG.duplicate(true)
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("mission_manager: config invalide, valeurs par défaut.")
		return DEFAULT_CFG.duplicate(true)
	# Complète les clés manquantes avec les valeurs par défaut.
	var cfg: Dictionary = DEFAULT_CFG.duplicate(true)
	for key in data.keys():
		cfg[key] = data[key]
	return cfg


## Génère une banque JOUABLE et VARIÉE (gabarit éprouvé : hall fermé → comptoir →
## coffre → sortie), paramétrée par la graine, le palier (tier 1..3) et le biome.
## Schéma identique aux fichiers JSON, donc tout le reste fonctionne sans changement.
func _generate_bank_cfg(seed_val: int, tier: int, biome: String, town_name: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var ox := 40.0
	var oy := 40.0
	var W: float = [0.0, 1180.0, 1380.0, 1560.0][tier]
	var H: float = [0.0, 820.0, 900.0, 980.0][tier]
	var cx := ox + W * 0.5
	var vshift := float(rng.randi_range(-1, 1)) * (W * 0.15)
	var gx: float = clampf(cx + vshift, ox + 280.0, ox + W - 280.0)   # axe coffre/passage
	var cyc := oy + H * rng.randf_range(0.47, 0.54)                   # profondeur comptoir variable
	var gap := 200.0                  # ouverture centrale (entrée + passage comptoir)
	var th := 24.0
	var nhw := 150.0                  # demi-largeur de la niche du coffre
	var nh := 150.0                   # hauteur des cloisons de niche
	var walls := []
	walls.append([ox, oy, W, th, 1])
	walls.append([ox, oy, th, H, 1])
	walls.append([ox + W - th, oy, th, H, 1])
	walls.append([ox, oy + H - th, (cx - gap * 0.5) - ox, th, 1])
	walls.append([cx + gap * 0.5, oy + H - th, (ox + W) - (cx + gap * 0.5), th, 1])
	walls.append([ox + 80.0, cyc, (gx - gap * 0.5) - (ox + 80.0), th, 0, 1])
	walls.append([gx + gap * 0.5, cyc, (ox + W - 80.0) - (gx + gap * 0.5), th, 0, 1])
	walls.append([gx - nhw - 12.0, oy + th, th, nh])
	walls.append([gx + nhw - 12.0, oy + th, th, nh])
	# Variante : bureau cloisonné dans un coin du fond (côté opposé au coffre),
	# avec une porte (130 px) ouverte sur la zone employés.
	var office := {}
	if rng.randf() < 0.5:
		var left_side := gx > cx
		var rx0: float = (ox + 24.0) if left_side else (ox + W - 24.0 - 250.0)
		var rx1 := rx0 + 250.0
		var ry1 := oy + 224.0
		if left_side:
			walls.append([rx1 - 12.0, oy + 24.0, th, 200.0])
			walls.append([rx0, ry1, 120.0, th])
		else:
			walls.append([rx0 - 12.0, oy + 24.0, th, 200.0])
			walls.append([rx1 - 120.0, ry1, 120.0, th])
		office = {"lx": rx0 + 70.0, "lx2": rx0 + 180.0, "ly0": oy + 92.0,
			"dx": rx0 + 125.0, "dy": oy + 150.0}

	var safe_y := oy + th + 86.0
	var safe_val := 450 + tier * 200 + rng.randi_range(0, 150)
	var safe := {"pos": [gx, safe_y], "value": safe_val, "open_time": 2.3 + tier * 0.2}

	var lobby_y := (cyc + (oy + H - th)) * 0.5
	var staff_y := ((oy + th + nh) + cyc) * 0.5

	var loot := []
	loot.append({"pos": [cx - 200.0 + rng.randf_range(-20, 20), cyc + 70.0], "value": 200})
	loot.append({"pos": [cx + 200.0 + rng.randf_range(-20, 20), cyc + 70.0], "value": 200})
	loot.append({"pos": [gx - 64.0, safe_y + 36.0], "value": 300})
	loot.append({"pos": [gx + 64.0, safe_y + 36.0], "value": 300})
	if tier >= 2:
		loot.append({"pos": [ox + 150.0, staff_y], "value": 150})
		loot.append({"pos": [ox + W - 150.0, staff_y], "value": 150})
	if tier >= 3:
		loot.append({"pos": [cx, lobby_y + 30.0], "value": 200})
	if not office.is_empty():
		loot.append({"pos": [office["lx"], office["ly0"]], "value": 200})
		loot.append({"pos": [office["lx2"], office["ly0"]], "value": 200})

	var guards := []
	guards.append({"route": [[ox + 120, lobby_y], [ox + W - 120, lobby_y],
		[ox + W - 120, lobby_y + 40], [ox + 120, lobby_y + 40]]})
	guards.append({"route": [[ox + 160, staff_y], [ox + W - 160, staff_y],
		[ox + W - 160, staff_y + 36], [ox + 160, staff_y + 36]]})
	if tier >= 2:
		guards.append({"route": [[gx - 90, cyc - 70], [gx + 90, cyc - 70],
			[gx + 90, cyc - 34], [gx - 90, cyc - 34]]})
	if tier >= 3:
		guards.append({"route": [[ox + 220, lobby_y + 90], [ox + W - 220, lobby_y + 90]]})

	var props := []
	for sgn in [-1.0, 1.0]:
		var cages := 2 if tier == 1 else 3
		for k in range(cages):
			props.append(["counter", gx + sgn * (gap * 0.5 + 105.0 + 70.0 * k), cyc - 10.0])
	props.append(["desk", ox + 160.0, oy + H * 0.30])
	props.append(["chair", ox + 160.0, oy + H * 0.30 + 46.0])
	props.append(["desk", ox + W - 160.0, oy + H * 0.30])
	props.append(["chair", ox + W - 160.0, oy + H * 0.30 + 46.0])
	props.append(["shelf", gx - nhw + 30.0, oy + 60.0])
	props.append(["shelf", gx + nhw - 30.0, oy + 60.0])
	props.append(["money", gx - 70.0, safe_y - 30.0])
	props.append(["money", gx + 70.0, safe_y - 30.0])
	props.append(["money", cx - 220.0, cyc - 40.0])
	props.append(["money", cx + 220.0, cyc - 40.0])
	props.append(["plant", ox + 120.0, oy + H - 120.0])
	props.append(["plant", ox + W - 120.0, oy + H - 120.0])
	props.append(["poster", ox + 54.0, lobby_y - 60.0])
	props.append(["poster", ox + W - 54.0, lobby_y + 60.0])
	# Ambiance (lustres, tableaux, tas d'or, guichetiers) — purement décoratif.
	props.append(["chandelier", cx, lobby_y])
	props.append(["chandelier", cx, staff_y])
	props.append(["painting", ox + 50.0, staff_y - 20.0])
	props.append(["painting", ox + W - 50.0, staff_y + 20.0])
	props.append(["goldpile", gx, safe_y + 70.0])
	props.append(["clerk", gx - 150.0, cyc - 44.0])
	props.append(["clerk", gx + 150.0, cyc - 44.0])
	if not office.is_empty():
		props.append(["desk", office["dx"], office["dy"]])
		props.append(["money", office["lx"], office["ly0"] - 30.0])
	# Solides UNIQUEMENT aux 4 coins (hors passage et hors rondes).
	props.append(["barrel", ox + 110.0, oy + H - 110.0])
	props.append(["crate", ox + W - 110.0, oy + H - 110.0])
	props.append(["crate", ox + 110.0, oy + 120.0])
	props.append(["barrel", ox + W - 110.0, oy + 120.0])

	var dyn: Array = []
	if rng.randf() < 0.6:
		dyn = [cx + rng.randf_range(-160.0, 160.0), lobby_y + 50.0]
	var hostages := []
	for _h in range(rng.randi_range(1, 2)):
		hostages.append([ox + rng.randf_range(0.24, 0.76) * W, cyc + rng.randf_range(70.0, 150.0), 150])
	var strongboxes := []
	for _b in range(rng.randi_range(1, 2)):
		var sbx_x: float = (ox + W * 0.30) if rng.randf() < 0.5 else (ox + W * 0.70)
		strongboxes.append([sbx_x, staff_y + rng.randf_range(-20.0, 30.0), 200 + tier * 60])
	var diff: String = ["", "Petite banque", "Banque de comté", "Grande banque"][tier]
	return {
		"dynamite": dyn,
		"hostages": hostages,
		"strongboxes": strongboxes,
		"name": town_name,
		"difficulty": diff,
		"biome": biome,
		"floor": [ox, oy, W, H],
		"walls": walls,
		"props": props,
		"player_start": [cx, oy + H - 70.0],
		"exit": [cx, oy + H - 34.0],
		"safe": safe,
		"loot": loot,
		"guards": guards,
	}


func _to_vec(a: Variant) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


# --- Construction du niveau ---

func _build_alarm() -> void:
	alarm = preload("res://scripts/alarm_system.gd").new()
	alarm.name = "AlarmSystem"
	add_child(alarm)
	alarm.alarm_changed.connect(_on_alarm_changed)
	alarm.global_alert_triggered.connect(_on_global_alert)


func _build_floor() -> void:
	# Emprise du sol lue depuis les données du niveau.
	var f: Variant = _cfg.get("floor", [20, 20, 820, 560])
	if f is Array and f.size() >= 4:
		_floor_rect = Rect2(float(f[0]), float(f[1]), float(f[2]), float(f[3]))
	else:
		_floor_rect = Rect2(20, 20, 820, 560)


func _build_walls() -> void:
	# Chaque mur = [x, y, w, h, outer?(0/1), low?(0/1)].
	for w in _cfg.get("walls", []):
		if not (w is Array) or w.size() < 4:
			continue
		var rect := Rect2(float(w[0]), float(w[1]), float(w[2]), float(w[3]))
		var outer: bool = w.size() > 4 and int(w[4]) != 0
		var low: bool = w.size() > 5 and int(w[5]) != 0
		_add_wall(rect, outer, low)


## Empreintes de collision des MEUBLES (le décor devient solide : on ne traverse
## plus tonneaux/caisses/bureaux). Le comptoir a déjà ses murets ; le coffre est
## dans l'ouverture, on ne le bloque donc pas.
const PROP_SOLID := {
	"barrel": Vector2(28, 28), "crate": Vector2(34, 34), "desk": Vector2(70, 42),
}

func _spawn_prop_solids() -> void:
	for p in _cfg.get("props", []):
		if not (p is Array) or p.size() < 3:
			continue
		var sz: Vector2 = PROP_SOLID.get(str(p[0]), Vector2.ZERO)
		if sz == Vector2.ZERO:
			continue
		var pos := Vector2(float(p[1]), float(p[2]))
		_add_solid(Rect2(pos - sz * 0.5, sz))


## Collision seule (sans visuel : le rendu du meuble est déjà fait par le renderer).
func _add_solid(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.position + rect.size * 0.5
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	body.add_child(cs)
	world.add_child(body)


## Crée la collision cartésienne du mur ; le visuel iso est géré par le renderer.
func _add_wall(rect: Rect2, outer := false, low := false) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.position + rect.size * 0.5
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	body.add_child(cs)
	world.add_child(body)
	_walls.append({"rect": rect, "outer": outer, "low": low})


# --- Entités ---

func _spawn_player() -> void:
	player = PlayerScene.instantiate()
	player.global_position = _to_vec(_cfg.get("player_start", [110, 540]))
	player.visible = false  # rendu par l'IsoRenderer
	world.add_child(player)
	player.caught.connect(_on_player_caught)
	player.loot_changed.connect(_on_loot_changed)


func _spawn_loot() -> void:
	for entry in _cfg.get("loot", []):
		var bag := LootBagScene.instantiate()
		bag.global_position = _to_vec(entry.get("pos", [0, 0]))
		bag.value = int(entry.get("value", 150))
		bag.visible = false
		world.add_child(bag)
		# On capture la position du sac (il est libéré juste après l'émission).
		bag.collected.connect(func(v): _on_loot_collected(v, bag.global_position))
		_loot_nodes.append(bag)
	_loot_total = _loot_nodes.size()


func _spawn_safe() -> void:
	var s: Dictionary = _cfg.get("safe", {})
	_safe = SafeScene.instantiate()
	_safe.global_position = _to_vec(s.get("pos", [1040, 540]))
	_safe.value = int(s.get("value", 500))
	# Upgrade "crochets" : le coffre s'ouvre plus vite.
	_safe.open_time = float(s.get("open_time", 2.5)) * SaveManager.safe_mult()
	_safe.visible = false
	world.add_child(_safe)
	_safe.opened.connect(_on_safe_opened)


func _spawn_exit() -> void:
	_exit = ExitZoneScene.instantiate()
	_exit.global_position = _to_vec(_cfg.get("exit", [1060, 100]))
	_exit.visible = false
	world.add_child(_exit)
	_exit.player_entered.connect(_on_exit_entered)


## Règle un garde selon le mode assist + l'upgrade discrétion.
## Coffres-forts SECONDAIRES ouvrables (E) : butin bonus, mêmes mécaniques.
func _spawn_strongboxes() -> void:
	var arr: Variant = _cfg.get("strongboxes", [])
	if not (arr is Array):
		return
	for sbx in arr:
		if not (sbx is Array) or sbx.size() < 2:
			continue
		var sf := SafeScene.instantiate()
		sf.global_position = Vector2(float(sbx[0]), float(sbx[1]))
		sf.value = int(sbx[2]) if sbx.size() > 2 else 250
		sf.open_time = (float(sbx[3]) if sbx.size() > 3 else 1.8) * SaveManager.safe_mult()
		sf.visible = false
		world.add_child(sf)
		sf.opened.connect(_on_strongbox_opened)
		_safes2.append(sf)


func _on_strongbox_opened(value: int) -> void:
	if player != null:
		player.add_safe_reward(value)
	AudioManager.play("safe")
	if _fx != null:
		for sf in _safes2:
			if is_instance_valid(sf) and sf._is_open:
				_fx.safe_burst(sf.global_position)
				break
	if hud.has_method("show_toast"):
		hud.show_toast("COFFRE FORCÉ ! +%d $" % value)


## Otages à libérer (optionnels) : civils retenus ; les atteindre rapporte un bonus.
func _spawn_hostages() -> void:
	var hs: Variant = _cfg.get("hostages", [])
	if not (hs is Array):
		return
	for h in hs:
		if not (h is Array) or h.size() < 2:
			continue
		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		area.monitoring = true
		area.global_position = Vector2(float(h[0]), float(h[1]))
		area.set_meta("value", int(h[2]) if h.size() > 2 else 150)
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = 20.0
		cs.shape = sh
		area.add_child(cs)
		world.add_child(area)
		area.body_entered.connect(_on_hostage_freed.bind(area))
		_hostages.append(area)


func _on_hostage_freed(body: Node, area: Area2D) -> void:
	if _mission_over or not body.is_in_group("player") or not is_instance_valid(area):
		return
	var value: int = int(area.get_meta("value", 150))
	_hostages_freed += 1
	if player != null:
		player.add_safe_reward(value)     # compte comme butin (sortie + score)
	AudioManager.play("pickup", 2.0)
	if _fx != null:
		_fx.loot_pickup(area.global_position)
	if hud.has_method("show_toast"):
		hud.show_toast("OTAGE LIBÉRÉ ! +%d $" % value)
	_hostages.erase(area)
	if _renderer != null:
		_renderer.hostages = _hostages
	_renderer.safes2 = _safes2
	area.queue_free()


## Dynamite ramassable (optionnelle) : la prendre SOUFFLE le coffre instantanément.
func _spawn_dynamite() -> void:
	var d: Variant = _cfg.get("dynamite", [])
	if not (d is Array) or d.size() < 2:
		return
	_dynamite = Area2D.new()
	_dynamite.collision_layer = 0
	_dynamite.collision_mask = 2          # détecte le joueur (layer 2)
	_dynamite.monitoring = true
	_dynamite.global_position = Vector2(float(d[0]), float(d[1]))
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 18.0
	cs.shape = sh
	_dynamite.add_child(cs)
	world.add_child(_dynamite)
	_dynamite.body_entered.connect(_on_dynamite_grabbed)


func _on_dynamite_grabbed(body: Node) -> void:
	if _dyn_used or _mission_over or not body.is_in_group("player"):
		return
	_dyn_used = true
	AudioManager.play("explosion", 4.0)
	if _fx != null:
		_fx.add_shake(11.0)
		if is_instance_valid(_safe):
			_fx.safe_burst(_safe.global_position)
	if hud.has_method("show_toast"):
		hud.show_toast("DYNAMITE ! Coffre soufflé !")
	if is_instance_valid(_safe) and _safe.has_method("force_open"):
		_safe.force_open()
	if is_instance_valid(_dynamite):
		_dynamite.visible = false
		_dynamite.queue_free()
	_dynamite = null
	if _renderer != null:
		_renderer.dynamite = null


func _apply_difficulty(g: Node) -> void:
	g.alarm_gain_mult = SaveManager.stealth_mult()
	# Notoriété : gardes plus nerveux (alarme + poursuite), bornée.
	var noto: int = SaveManager.notoriety
	g.alarm_gain_mult *= 1.0 + 0.035 * noto
	if GameManager.assist:
		g.alarm_gain_mult *= 0.5     # alarme monte 2x moins vite
		g.detect_mult = 0.6          # détection plus lente
		g.chase_mult = 0.85          # poursuite un peu plus lente que le joueur
		g.fire_mult = 1.7            # tire moins souvent
		g.lethal_touch = false       # le contact blesse au lieu de tuer net


func _spawn_guards() -> void:
	for entry in _cfg.get("guards", []):
		var route := PackedVector2Array()
		for pt in entry.get("route", []):
			route.append(_to_vec(pt))
		if route.is_empty():
			continue
		var g := GuardScene.instantiate()
		g.patrol_points = route
		g.global_position = route[0]
		if str(entry.get("kind", "")) == "sniper":
			g.kind = "sniper"
		g.player = player
		g.alarm = alarm
		_apply_difficulty(g)
		g.visible = false
		world.add_child(g)
		g.player_caught.connect(_on_player_caught)
		_guards.append(g)


func _connect_hud() -> void:
	if hud.has_method("set_money"):
		hud.set_money(SaveManager.total_money)
	if hud.has_method("set_loot"):
		hud.set_loot(0, 0)
	if hud.has_method("set_alarm"):
		hud.set_alarm(0.0)
	if hud.has_method("set_state"):
		hud.set_state(false)
	if hud.has_method("set_health"):
		hud.set_health(player.hp, player.max_hp)
	if hud.has_method("set_ammo"):
		hud.set_ammo(player.ammo, player.cap, false)


# --- Boucle ---

func _process(delta: float) -> void:
	_update_focus(delta)
	# La caméra (suivi + shake) est gérée par l'IsoRenderer lui-même.
	if _mission_over:
		return
	_elapsed += delta
	# État discret / alerte = au moins un garde qui enquête ou poursuit.
	var engaged := false
	for g in _guards:
		if is_instance_valid(g) and g.has_method("is_engaged") and g.is_engaged():
			engaged = true
			break
	# Feedback "VU !" au moment où un garde commence à nous repérer.
	if engaged and not _was_engaged and not (alarm != null and alarm.global_alert):
		if hud.has_method("show_toast"):
			hud.show_toast("VU !")
		AudioManager.play("hit_guard", -6.0)
	_was_engaged = engaged
	if hud.has_method("set_state"):
		hud.set_state(engaged or (alarm != null and alarm.global_alert))
	# Poussière de pas pendant le déplacement.
	_foot_t -= delta
	if _fx != null and player != null and player.is_moving and _foot_t <= 0.0:
		_fx.foot_dust(player.global_position)
		_foot_t = 0.18
	_move_coach(delta)


## Mode tactique "Sang-froid" : ralentit le monde tout en gardant le joueur
## réactif (vitesse compensée). Jauge qui se vide à l'usage et se recharge au repos.
func _update_focus(delta: float) -> void:
	var ts: float = Engine.time_scale
	var rdelta: float = delta / maxf(0.05, ts)
	var want: bool = (not _mission_over) and InputManager.is_focus_held() and _focus > 0.02
	if want:
		_focus = maxf(0.0, _focus - FOCUS_DRAIN * rdelta)
		Engine.time_scale = FOCUS_SLOW
		if player != null:
			player.focus_boost = 1.0 / FOCUS_SLOW
		_focus_active = true
	else:
		Engine.time_scale = 1.0
		if player != null:
			player.focus_boost = 1.0
		_focus_active = false
		_focus = minf(1.0, _focus + FOCUS_RECHARGE * rdelta)
	if _renderer != null:
		_renderer.focus = _focus
		_renderer.focus_active = _focus_active


## Renfort : un shérif supplémentaire surgit de la sortie quand l'alarme éclate.
func _spawn_reinforcement() -> void:
	if _reinforced:
		return
	_reinforced = true
	# Renfort générique : surgit de la sortie et fonce vers le centre du niveau.
	var route := PackedVector2Array([
		_exit.global_position, _floor_rect.get_center(),
	])
	var g := GuardScene.instantiate()
	g.patrol_points = route
	g.global_position = _exit.global_position
	g.player = player
	g.alarm = alarm
	g.bullet_system = _bullets
	_apply_difficulty(g)
	g.visible = false
	world.add_child(g)
	g.player_caught.connect(_on_player_caught)
	_guards.append(g)
	if hud.has_method("show_toast"):
		hud.show_toast("RENFORTS !")


## Survivants + non-combattants rejoignent la BANDE FIDÈLE (réembauche gratuite).
func _promote_crew_to_gang() -> void:
	var alive := {}
	for a in _allies:
		if is_instance_valid(a):
			alive[str(a.get_meta("cname", ""))] = true
	for c in GameManager.crew:
		var role := str(c.get("role", ""))
		var nm := str(c.get("name", ""))
		if role == "gunman" or role == "marksman":
			if alive.has(nm):
				SaveManager.add_loyal(nm, role)
		else:
			SaveManager.add_loyal(nm, role)


## Score de mission : butin + bonus discrétion + bonus temps.
func _compute_score() -> Dictionary:
	var loot: int = _loot_value
	# Discrétion : récompense de ne pas avoir déclenché l'alarme générale, et
	# d'avoir gardé la jauge basse.
	var stealth := 0
	if not _alarm_triggered:
		stealth += 200
	stealth += int(round((1.0 - clampf(_alarm_peak / 100.0, 0.0, 1.0)) * 150.0))
	# Temps : prime à la rapidité (sous 2 minutes).
	var time_bonus: int = max(0, int(round((120.0 - _elapsed) * 2.0)))
	var contract := int(_contract.get("bonus", 0)) if _contract_done() else 0
	var crew := (200 * GameManager.crew_count_role("scout") + 120 * _allies.size()) if GameManager.coach_mission else 0
	return {
		"loot": loot,
		"stealth": stealth,
		"time": time_bonus,
		"contract": contract,
		"crew": crew,
		"total": loot + stealth + time_bonus + contract + crew,
	}


# --- Signaux ---

func _on_loot_collected(value: int, pos := Vector2.ZERO) -> void:
	if player != null:
		player.add_loot(value)
	AudioManager.play("pickup")
	if _fx != null:
		_fx.loot_pickup(pos)
	if hud.has_method("show_toast"):
		hud.show_toast("+%d $ !" % value)


func _on_loot_changed(bags: int, value: int) -> void:
	_loot_bags = bags
	_loot_value = value
	if hud.has_method("set_loot"):
		hud.set_loot(bags, value)
	_update_objective()


func _on_safe_opened(value: int) -> void:
	_safe_open = true
	if player != null:
		player.add_safe_reward(value)
	AudioManager.play("safe")
	if _fx != null and _safe != null:
		_fx.safe_burst(_safe.global_position)
	if hud.has_method("show_toast"):
		hud.show_toast("COFFRE OUVERT ! +%d $" % value)
	_update_objective()


func _on_alarm_changed(value: float) -> void:
	_alarm_peak = max(_alarm_peak, value)
	if hud.has_method("set_alarm"):
		hud.set_alarm(value)


func _on_global_alert() -> void:
	if hud.has_method("show_toast"):
		hud.show_toast("ALARME ! TOUS AUX ARMES !")
	if hud.has_method("flash"):
		hud.flash(Color(0.9, 0.1, 0.1, 0.5))
	if _fx != null:
		_fx.add_shake(8.0)
	AudioManager.play("alarm", 2.0)
	_alarm_triggered = true
	_spawn_reinforcement()


func _on_exit_entered() -> void:
	if _mission_over:
		return
	if player != null and player.has_loot():
		_end_mission(true)
	else:
		# Pas de butin : on ne sort pas les mains vides.
		if hud.has_method("show_toast"):
			hud.show_toast("Reviens avec du butin !")
		if _exit != null and _exit.has_method("rearm"):
			_exit.rearm()


func _on_guard_killed(g: Node) -> void:
	if not is_instance_valid(g):
		return
	_guards_killed += 1
	if g.has_method("stop"):
		g.stop()
	# Animation de mort : on confie un "corps qui tombe" au renderer avant de
	# libérer le garde.
	if _renderer != null and _renderer.has_method("add_corpse"):
		_renderer.add_corpse(g.global_position, g.get_facing())
	if _fx != null:
		_fx.add_shake(4.0)
	AudioManager.play("hit_guard")
	_guards.erase(g)
	g.queue_free()
	if hud.has_method("show_toast"):
		hud.show_toast("Garde abattu !")


func _on_guard_hit(_g: Node) -> void:
	# Garde touché mais encore debout.
	AudioManager.play("hit_guard", -4.0)
	if _fx != null:
		_fx.add_shake(2.0)


func _on_player_hit() -> void:
	if player != null:
		player.take_damage(1)


func _on_player_health(current_hp: int) -> void:
	if hud.has_method("set_health"):
		hud.set_health(current_hp, player.max_hp)
	if current_hp > 0 and hud.has_method("show_toast"):
		hud.show_toast("Touché ! PV: %d" % current_hp)


func _on_player_ammo(in_cylinder: int, capacity: int, reloading: bool) -> void:
	if hud.has_method("set_ammo"):
		hud.set_ammo(in_cylinder, capacity, reloading)


func _on_player_caught() -> void:
	if _mission_over:
		return
	_end_mission(false)


# --- Fin de mission ---

func _update_objective() -> void:
	if not hud.has_method("set_objective"):
		return
	var text := ""
	if _loot_bags == 0:
		text = "Récupère du butin ($)"
	elif not _safe_open:
		text = "Ouvre le coffre, puis file vers la SORTIE"
	else:
		text = "Atteins la SORTIE (verte)"
	if GameManager.coach_mission and not _safe_open:
		text = "Rattrape et PILLE la diligence (maintiens E)"
	if not _contract.is_empty():
		text += "   ·   Contrat: " + str(_contract.get("desc", ""))
	hud.set_objective(text)


func _end_mission(success: bool) -> void:
	_mission_over = true
	Engine.time_scale = 1.0
	if player != null:
		player.focus_boost = 1.0
	_focus_active = false
	if GameManager.coach_mission and success:
		_promote_crew_to_gang()
	if _bullets != null and _bullets.has_method("stop"):
		_bullets.stop()
	for g in _guards:
		if is_instance_valid(g) and g.has_method("stop"):
			g.stop()
	if player != null:
		player.get_caught()  # fige le joueur
	AudioManager.play("win" if success else "lose", 2.0)
	if hud.has_method("show_toast"):
		var msg := "FUITE RÉUSSIE !" if success else "REPÉRÉ ! ÉCHEC"
		if success and _contract_done():
			msg += "   CONTRAT +%d $" % int(_contract.get("bonus", 0))
		hud.show_toast(msg)
	await get_tree().create_timer(0.9).timeout
	GameManager.finish_mission(success, _loot_value, _loot_bags, _compute_score())
