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
	"player_start": [590, 575],          # entrée (hall public, en bas)
	"exit": [110, 560],                  # porte d'entrée (front, bas-gauche)
	"safe": {"pos": [1015, 170], "value": 500, "open_time": 2.5},  # dans le coffre-fort
	"loot": [
		{"pos": [935, 175], "value": 250},   # dans la salle des coffres
		{"pos": [650, 300], "value": 150},   # derrière le comptoir
		{"pos": [350, 520], "value": 150},   # dans le hall
	],
	"guards": [
		{"route": [[480, 320], [1000, 320], [1000, 300], [480, 300]]},  # zone personnel
		{"route": [[250, 500], [820, 500], [820, 470], [250, 470]]},    # hall public
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
var _renderer_home := Vector2.ZERO   # position de repos (pour le screen-shake)

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
	_bullets.player_hit.connect(_on_player_hit)
	player.bullet_system = _bullets
	player.health_changed.connect(_on_player_health)
	player.ammo_changed.connect(_on_player_ammo)
	for g in _guards:
		g.bullet_system = _bullets


## Re-fit du niveau et resynchronisation des effets quand l'écran change de taille.
func _on_viewport_resized() -> void:
	if not is_instance_valid(_renderer) or not _renderer.has_method("refit"):
		return
	_renderer_home = _renderer.refit()
	if is_instance_valid(_fx):
		_fx.scale = _renderer.scale
		_fx.position = _renderer_home


func _build_effects() -> void:
	_fx = preload("res://scripts/effects.gd").new()
	_fx.name = "Effects"
	# Les effets partagent le MÊME zoom/position que le renderer pour rester
	# alignés sur les entités (le shake ne décale que le renderer).
	_fx.iso_offset = Vector2.ZERO
	_fx.scale = _renderer.scale
	_fx.position = _renderer_home
	add_child(_fx)
	_renderer.fx = _fx
	# Branche les effets sur les évènements de combat.
	_bullets.impact.connect(func(pos, dir, friendly): _fx.impact_spark(pos, dir, friendly))
	_bullets.wall_impact.connect(func(pos): _fx.wall_puff(pos))
	player.fired.connect(func(pos, dir):
		_fx.muzzle_flash(pos, dir)
		_fx.add_shake(3.0))
	player.damaged.connect(func():
		if hud.has_method("flash"):
			hud.flash(Color(0.8, 0.0, 0.0, 0.45))
		_fx.add_shake(7.0))


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
	_renderer_home = _renderer.position
	# Re-ajuste le zoom si la fenêtre/écran change de taille (navigateur, mobile).
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
	_floor_rect = Rect2(20, 20, 1140, 600)


func _build_walls() -> void:
	# Murs extérieurs (épaisseur 20). Porte d'entrée = trou dans le mur gauche.
	_add_wall(Rect2(0, 0, 1180, 20), true)            # haut
	_add_wall(Rect2(0, 620, 1180, 20), true)          # bas
	_add_wall(Rect2(1160, 0, 20, 640), true)          # droite
	_add_wall(Rect2(0, 0, 20, 500), true)             # gauche (au-dessus de la porte)
	_add_wall(Rect2(0, 600, 20, 40), true)            # gauche (sous la porte)

	# --- Salle des coffres (vault) fermée, haut-droite, avec une ouverture ---
	# Cloison verticale gauche du coffre (x=820), trou d'entrée vers y=250..330.
	_add_wall(Rect2(820, 20, 24, 230))                # haut du mur vertical
	_add_wall(Rect2(820, 330, 24, 60))                # bas du mur vertical
	# Cloison horizontale basse du coffre (y=370), de x=820 à droite.
	_add_wall(Rect2(844, 366, 316, 24))

	# --- Comptoir des guichets : sépare hall (bas) du personnel (haut) ---
	# Cloison basse du comptoir à y=360, avec un passage (gap) vers x=560..660.
	_add_wall(Rect2(180, 354, 360, 22))               # tronçon gauche
	_add_wall(Rect2(680, 354, 140, 22))               # tronçon droit (jusqu'au vault)

	# --- Bureau du directeur (haut-gauche), petite alcôve ---
	_add_wall(Rect2(180, 110, 22, 150))               # cloison verticale du bureau
	_add_wall(Rect2(20, 240, 182, 22))                # cloison horizontale du bureau


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
	if hud.has_method("set_ammo"):
		hud.set_ammo(player.ammo, player.CYLINDER, false)


# --- Boucle ---

func _process(_delta: float) -> void:
	# Applique le screen-shake en décalant le renderer autour de sa position de repos.
	if _fx != null and _renderer != null:
		_renderer.position = _renderer_home + _fx.get_shake_offset()
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
	if hud.has_method("flash"):
		hud.flash(Color(0.9, 0.1, 0.1, 0.5))
	if _fx != null:
		_fx.add_shake(8.0)


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
	if hud.has_method("show_toast"):
		hud.show_toast("MISSION RÉUSSIE" if success else "REPÉRÉ ! ÉCHEC")
	await get_tree().create_timer(0.9).timeout
	GameManager.finish_mission(success, _loot_value, _loot_bags)
