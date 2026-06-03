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

const CONFIG_PATH := "res://data/mission_01.json"

# Configuration par défaut si le fichier de données est absent ou invalide.
# Plan de banque réaliste : hall public (bas), comptoir des guichets (milieu,
# avec passage), salle des coffres fermée (haut-droite), bureau (haut-gauche).
const DEFAULT_CFG := {
	"player_start": [560, 600],          # entrée (grand hall public, en bas)
	"exit": [95, 555],                   # porte d'entrée (front, bas-gauche)
	"safe": {"pos": [1015, 170], "value": 600, "open_time": 2.5},  # dans le coffre-fort
	"loot": [
		{"pos": [935, 175], "value": 250},    # salle des coffres
		{"pos": [1060, 300], "value": 250},   # salle des coffres (fond)
		{"pos": [650, 300], "value": 150},    # derrière le comptoir
		{"pos": [330, 520], "value": 150},    # hall (gauche)
		{"pos": [760, 760], "value": 150},    # grand hall (bas)
		{"pos": [1330, 250], "value": 200},   # aile droite (haut)
		{"pos": [1330, 760], "value": 200},   # aile droite (bas)
	],
	"guards": [
		{"route": [[210, 320], [800, 320], [800, 300], [210, 300]]},      # zone personnel
		{"route": [[120, 720], [1380, 720], [1380, 760], [120, 760]]},    # grand hall
		{"route": [[900, 120], [1080, 120], [1080, 320], [900, 320]]},    # salle des coffres
		{"route": [[1340, 120], [1340, 420], [1440, 420], [1440, 120]]},  # aile droite
	],
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


func _ready() -> void:
	randomize()
	_cfg = _load_config()
	_build_alarm()
	_build_floor()
	_build_walls()
	_spawn_player()
	_spawn_loot()
	_spawn_safe()
	_spawn_exit()
	_spawn_guards()
	_build_bullets()
	_build_iso_renderer()
	_build_effects()
	_connect_hud()
	_update_objective()


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

## Charge data/mission_01.json. Retombe sur DEFAULT_CFG si absent/invalide.
func _load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return DEFAULT_CFG.duplicate(true)
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
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
	# Le sol est dessiné par l'IsoRenderer ; on mémorise juste son emprise.
	# Grande banque : vaste hall (bas), zone personnel + bureau (haut-gauche),
	# salle des coffres (haut-droite) et aile/couloir droit.
	_floor_rect = Rect2(20, 20, 1480, 840)


func _build_walls() -> void:
	# --- Murs extérieurs (épaisseur 20). Porte d'entrée = trou dans le mur gauche.
	_add_wall(Rect2(0, 0, 1520, 20), true)            # haut
	_add_wall(Rect2(0, 860, 1520, 20), true)          # bas
	_add_wall(Rect2(1500, 0, 20, 880), true)          # droite
	_add_wall(Rect2(0, 0, 20, 500), true)             # gauche (au-dessus de la porte)
	_add_wall(Rect2(0, 600, 20, 260), true)           # gauche (sous la porte)

	# --- Salle des coffres (vault) fermée, haut-droite, avec une entrée ---
	# Cloison verticale gauche (x=820), ouverture d'accès vers y=250..330.
	_add_wall(Rect2(820, 20, 24, 230))                # haut du mur vertical
	_add_wall(Rect2(820, 330, 24, 40))                # bas du mur vertical
	_add_wall(Rect2(844, 366, 312, 24))               # cloison basse du coffre
	_add_wall(Rect2(1156, 20, 24, 346))               # paroi droite du coffre (referme)

	# --- Comptoir des guichets : sépare hall (bas) du personnel (haut) ---
	# Cloison basse du comptoir à y=354, avec un passage (gap) vers x=540..680.
	_add_wall(Rect2(180, 354, 360, 22))               # tronçon gauche
	_add_wall(Rect2(680, 354, 140, 22))               # tronçon droit (jusqu'au vault)

	# --- Bureau du directeur (haut-gauche), petite alcôve ---
	_add_wall(Rect2(180, 110, 22, 150))               # cloison verticale du bureau
	_add_wall(Rect2(20, 240, 182, 22))                # cloison horizontale du bureau

	# --- Aile droite : petit office cloisonné (cover), accès large par le bas ---
	_add_wall(Rect2(1180, 470, 22, 200))              # cloison verticale de l'aile
	_add_wall(Rect2(1180, 470, 200, 22))              # cloison horizontale de l'aile


## Crée la collision cartésienne du mur ; le visuel iso est géré par le renderer.
func _add_wall(rect: Rect2, outer := false) -> void:
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
	_walls.append({"rect": rect, "outer": outer})


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
		g.player = player
		g.alarm = alarm
		g.alarm_gain_mult = SaveManager.stealth_mult()
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
		hud.set_health(player.hp, player.MAX_HP)
	if hud.has_method("set_ammo"):
		hud.set_ammo(player.ammo, player.CYLINDER, false)


# --- Boucle ---

func _process(delta: float) -> void:
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


## Renfort : un shérif supplémentaire surgit de la sortie quand l'alarme éclate.
func _spawn_reinforcement() -> void:
	if _reinforced:
		return
	_reinforced = true
	var route := PackedVector2Array([
		_exit.global_position + Vector2(40, 0),
		Vector2(600, 400), Vector2(900, 300),
	])
	var g := GuardScene.instantiate()
	g.patrol_points = route
	g.global_position = _exit.global_position
	g.player = player
	g.alarm = alarm
	g.bullet_system = _bullets
	g.alarm_gain_mult = SaveManager.stealth_mult()
	g.visible = false
	world.add_child(g)
	g.player_caught.connect(_on_player_caught)
	_guards.append(g)
	if hud.has_method("show_toast"):
		hud.show_toast("RENFORTS !")


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
	return {
		"loot": loot,
		"stealth": stealth,
		"time": time_bonus,
		"total": loot + stealth + time_bonus,
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
		hud.set_health(current_hp, player.MAX_HP)
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
	hud.set_objective(text)


func _end_mission(success: bool) -> void:
	_mission_over = true
	if _bullets != null and _bullets.has_method("stop"):
		_bullets.stop()
	for g in _guards:
		if is_instance_valid(g) and g.has_method("stop"):
			g.stop()
	if player != null:
		player.get_caught()  # fige le joueur
	AudioManager.play("win" if success else "lose", 2.0)
	if hud.has_method("show_toast"):
		hud.show_toast("FUITE RÉUSSIE !" if success else "REPÉRÉ ! ÉCHEC")
	await get_tree().create_timer(0.9).timeout
	GameManager.finish_mission(success, _loot_value, _loot_bags, _compute_score())
