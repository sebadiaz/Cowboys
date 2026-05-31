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
const DEFAULT_CFG := {
	"player_start": [110, 540],
	"exit": [1060, 100],
	"safe": {"pos": [1040, 540], "value": 500, "open_time": 2.5},
	"loot": [
		{"pos": [470, 470], "value": 150},
		{"pos": [900, 470], "value": 150},
		{"pos": [520, 150], "value": 200},
	],
	"guards": [
		{"route": [[500, 150], [500, 540], [250, 540], [250, 150]]},
		{"route": [[760, 300], [760, 540], [980, 540], [980, 300]]},
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

var _mission_over := false
var _safe_open := false
var _loot_bags := 0
var _loot_value := 0


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
	_connect_hud()
	_update_objective()


func _build_bullets() -> void:
	_bullets = preload("res://scripts/bullet_system.gd").new()
	_bullets.name = "BulletSystem"
	_bullets.player = player
	_bullets.guards = _guards
	add_child(_bullets)
	_bullets.guard_killed.connect(_on_guard_killed)
	_bullets.player_hit.connect(_on_player_hit)
	player.bullet_system = _bullets
	player.health_changed.connect(_on_player_health)
	for g in _guards:
		g.bullet_system = _bullets


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
	_floor_rect = Rect2(20, 20, 1140, 600)


func _build_walls() -> void:
	# Murs extérieurs (épaisseur 20).
	_add_wall(Rect2(0, 0, 1180, 20), true)
	_add_wall(Rect2(0, 620, 1180, 20), true)
	_add_wall(Rect2(0, 0, 20, 640), true)
	_add_wall(Rect2(1160, 0, 20, 640), true)
	# Comptoirs intérieurs.
	_add_wall(Rect2(340, 120, 50, 240))
	_add_wall(Rect2(620, 280, 50, 240))
	_add_wall(Rect2(800, 160, 240, 50))


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
		bag.collected.connect(_on_loot_collected)
		_loot_nodes.append(bag)


func _spawn_safe() -> void:
	var s: Dictionary = _cfg.get("safe", {})
	_safe = SafeScene.instantiate()
	_safe.global_position = _to_vec(s.get("pos", [1040, 540]))
	_safe.value = int(s.get("value", 500))
	_safe.open_time = float(s.get("open_time", 2.5))
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


# --- Boucle ---

func _process(_delta: float) -> void:
	if _mission_over:
		return
	# État discret / alerte = au moins un garde qui enquête ou poursuit.
	var engaged := false
	for g in _guards:
		if is_instance_valid(g) and g.has_method("is_engaged") and g.is_engaged():
			engaged = true
			break
	if hud.has_method("set_state"):
		hud.set_state(engaged or (alarm != null and alarm.global_alert))


# --- Signaux ---

func _on_loot_collected(value: int) -> void:
	if player != null:
		player.add_loot(value)


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
	if hud.has_method("show_toast"):
		hud.show_toast("Coffre ouvert ! +%d $" % value)
	_update_objective()


func _on_alarm_changed(value: float) -> void:
	if hud.has_method("set_alarm"):
		hud.set_alarm(value)


func _on_global_alert() -> void:
	if hud.has_method("show_toast"):
		hud.show_toast("ALERTE GÉNÉRALE !")


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
	_guards.erase(g)
	g.queue_free()
	if hud.has_method("show_toast"):
		hud.show_toast("Garde abattu !")


func _on_player_hit() -> void:
	if player != null:
		player.take_damage(1)


func _on_player_health(current_hp: int) -> void:
	if hud.has_method("set_health"):
		hud.set_health(current_hp, player.MAX_HP)
	if current_hp > 0 and hud.has_method("show_toast"):
		hud.show_toast("Touché ! PV: %d" % current_hp)


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
	if hud.has_method("show_toast"):
		hud.show_toast("MISSION RÉUSSIE" if success else "REPÉRÉ ! ÉCHEC")
	await get_tree().create_timer(0.9).timeout
	GameManager.finish_mission(success, _loot_value, _loot_bags)
