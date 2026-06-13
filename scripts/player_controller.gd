extends CharacterBody2D
## player_controller.gd
## Cowboy contrôlable en 8 directions. Suit InputManager (clavier + tactile).
## Ramasse le butin, peut être capturé par un garde en alerte.

signal loot_changed(loot_bags: int, loot_value: int)
signal caught()
signal health_changed(hp: int)
signal ammo_changed(in_cylinder: int, capacity: int, reloading: bool)
signal fired(muzzle_pos: Vector2, dir: Vector2)
signal damaged()

const SPEED := 220.0
const BODY_RADIUS := 14.0
const MAX_HP := 3
const FIRE_RATE := 0.32      # secondes entre deux tirs
const MUZZLE := 16.0         # distance du canon
const RECOIL_TIME := 0.12    # durée du recul visuel
const CYLINDER := 6          # six-coups
const RELOAD_TIME := 1.6     # rechargement (lent, sensible)

var loot_bags: int = 0
var loot_value: int = 0
var is_caught: bool = false
var facing := Vector2.DOWN
var max_hp: int = MAX_HP       # ajusté selon le mode assist
var hp: int = MAX_HP
var bullet_system: Node = null
var iso_renderer: Node2D = null   # pour convertir la position du clic en point monde
var ammo: int = CYLINDER
var cap: int = CYLINDER          # capacité du barillet (CYLINDER + upgrade)
var focus_boost: float = 1.0     # compensation de vitesse en mode Sang-froid
var is_moving: bool = false   # le tir n'est possible qu'à l'arrêt
var recoil: float = 0.0       # 0..1, décroît, pour l'animation de recul
var walk_phase: float = 0.0   # phase d'animation de marche
var speed_mult: float = 1.0   # upgrade "vitesse"
var reload_mult: float = 1.0  # upgrade "recharge"
var _fire_cd: float = 0.0
var _reload_t: float = 0.0    # > 0 = rechargement en cours
var _invuln_t: float = 0.0    # > 0 = invulnérabilité temporaire (anti-rafale)

## Fenêtre d'invulnérabilité après un coup : empêche d'être fondu par plusieurs
## tireurs simultanés (typique en restant au coffre). Plus longue en assist.
func _invuln_window() -> float:
	return (0.8 if GameManager.assist else 0.45) * SaveManager.invuln_mult()


func _ready() -> void:
	# Applique les upgrades persistés (SaveManager est un autoload).
	speed_mult = SaveManager.speed_mult()
	reload_mult = SaveManager.reload_mult()
	# Mode assist (prototype) : plus de PV pour une vraie marge d'erreur.
	max_hp = (7 if GameManager.assist else MAX_HP) + SaveManager.hp_bonus()
	hp = max_hp
	cap = CYLINDER + SaveManager.ammo_bonus()
	ammo = cap


func _reload_time() -> float:
	return RELOAD_TIME * reload_mult


func _physics_process(delta: float) -> void:
	if _invuln_t > 0.0:
		_invuln_t = max(0.0, _invuln_t - delta)
	if is_caught:
		velocity = Vector2.ZERO
		return
	var input := InputManager.get_move_vector()
	# Contrôles alignés écran : on pivote l'entrée vers l'espace monde isométrique.
	var dir := Iso.screen_to_world(input)
	if dir.length() > 1.0:
		dir = dir.normalized()
	velocity = dir * SPEED * speed_mult * focus_boost
	is_moving = dir.length() > 0.05
	if is_moving:
		facing = dir.normalized()
		walk_phase += delta * 10.0
	else:
		walk_phase = 0.0
	recoil = max(0.0, recoil - delta / RECOIL_TIME)
	move_and_slide()
	_handle_fire(delta)


func _handle_fire(delta: float) -> void:
	_fire_cd = max(0.0, _fire_cd - delta)

	# Rechargement en cours (le six-coups prend du temps à recharger).
	if _reload_t > 0.0:
		_reload_t = max(0.0, _reload_t - delta)
		if _reload_t <= 0.0:
			ammo = cap
			ammo_changed.emit(ammo, cap, false)
		return

	# Rechargement manuel (touche R / bouton tactile).
	if InputManager.is_reload_pressed() and ammo < cap:
		_start_reload()
		return

	# Pas de tir en mouvement : il faut s'arrêter pour dégainer et viser.
	if is_moving:
		return

	if _fire_cd <= 0.0 and bullet_system != null and InputManager.is_fire_pressed():
		if ammo <= 0:
			_start_reload()   # barillet vide -> rechargement auto
			return
		var dir := _aim_direction()
		facing = dir
		bullet_system.spawn(global_position + dir * MUZZLE, dir, true)
		ammo -= 1
		recoil = 1.0
		ammo_changed.emit(ammo, cap, false)
		fired.emit(global_position + dir * MUZZLE, dir)
		_fire_cd = FIRE_RATE * SaveManager.firerate_mult()


func _start_reload() -> void:
	if _reload_t > 0.0:
		return
	_reload_t = _reload_time()
	AudioManager.play("reload")
	ammo_changed.emit(ammo, cap, true)


func get_reload_ratio() -> float:
	return 1.0 - (_reload_t / _reload_time()) if _reload_t > 0.0 else 1.0


## Direction de tir : vers le point pointé (souris/clic) si dispo, sinon vers la
## direction regardée (cas du bouton tactile TIR sans curseur).
func _aim_direction() -> Vector2:
	if iso_renderer != null and InputManager.is_aiming_with_pointer():
		# Souris dans le repère local du renderer iso -> monde cartésien.
		var target := Iso.unproject(iso_renderer.get_local_mouse_position())
		var to_target := target - global_position
		if to_target.length() > 4.0:
			return to_target.normalized()
	return facing


## Encaisse un tir de garde. À 0 PV, le joueur tombe (échec).
## Ignoré pendant la fenêtre d'invulnérabilité (anti-rafale, contre-jeu équitable).
func take_damage(amount: int = 1) -> void:
	if is_caught or _invuln_t > 0.0:
		return
	_invuln_t = _invuln_window()
	hp = max(0, hp - amount)
	health_changed.emit(hp)
	damaged.emit()
	if hp <= 0:
		get_caught()


## True pendant l'invulnérabilité (le renderer fait clignoter le joueur).
func is_invulnerable() -> bool:
	return _invuln_t > 0.0


## Ajoute un sac de butin (appelé par LootBag via mission_manager).
func add_loot(value: int) -> void:
	loot_bags += 1
	loot_value += int(round(value * SaveManager.loot_mult()))
	loot_changed.emit(loot_bags, loot_value)


## Bonus de valeur du coffre (sans incrémenter le nombre de sacs).
func add_safe_reward(value: int) -> void:
	loot_value += int(round(value * SaveManager.loot_mult()))
	loot_changed.emit(loot_bags, loot_value)


func has_loot() -> bool:
	# On peut filer dès qu'on a ramassé quelque chose : un sac OU le coffre.
	return loot_bags > 0 or loot_value > 0


func get_caught() -> void:
	if is_caught:
		return
	is_caught = true
	velocity = Vector2.ZERO
	caught.emit()


func _draw() -> void:
	# Ombre portée.
	draw_circle(Vector2(0, 6), BODY_RADIUS, Color(0, 0, 0, 0.25))
	# Corps marron.
	draw_circle(Vector2.ZERO, BODY_RADIUS, Color(0.45, 0.27, 0.13))
	# Chapeau (couronne + bord), décalé vers la direction regardée.
	var hat_offset := facing * 4.0
	draw_circle(hat_offset, BODY_RADIUS + 3.0, Color(0.30, 0.18, 0.08))
	draw_circle(hat_offset, BODY_RADIUS - 3.0, Color(0.38, 0.23, 0.10))
	# Petite étoile claire pour repérer l'avant.
	draw_circle(facing * (BODY_RADIUS - 2.0), 3.0, Color(0.95, 0.85, 0.55))
