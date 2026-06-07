extends CharacterBody2D
## guard_ai.gd
## Garde avec patrouille, détection progressive et MÉMOIRE du joueur.
## États : PATROL (ronde) → SUSPECT (enquête) → SEARCH (fouille la dernière
## position connue) → ALERT (poursuite + tir). En alerte, s'il touche le joueur,
## la mission échoue.

signal player_caught()

enum State { PATROL, SUSPECT, SEARCH, ALERT }

const PATROL_SPEED := 72.0
const SUSPECT_SPEED := 45.0
const SEARCH_SPEED := 90.0
const CHASE_SPEED := 165.0
const BODY_RADIUS := 14.0
const CATCH_DISTANCE := 26.0
const WAYPOINT_REACHED := 8.0
const SEARCH_TIME := 4.0        # durée de fouille après avoir perdu le joueur

# Cinétique de la détection.
const DETECT_RISE := 1.15      # par seconde quand le joueur est vu
const DETECT_FALL := 0.5       # par seconde quand il ne l'est plus
const SUSPECT_THRESHOLD := 0.22
const ALERT_THRESHOLD := 1.0
const ALARM_GAIN := 32.0       # contribution à la jauge globale / seconde

var patrol_points: PackedVector2Array = PackedVector2Array()
var player: Node2D = null
var alarm: Node = null
var bullet_system: Node = null
var active: bool = true
var alarm_gain_mult: float = 1.0   # réduit par l'upgrade "discrétion"
var detect_mult: float = 1.0       # vitesse de détection (assist = plus lent)
var chase_mult: float = 1.0        # vitesse de poursuite (assist = plus lent)
var fire_mult: float = 1.0         # cadence de tir (assist = plus lent)
var lethal_touch: bool = true      # contact mortel (false en assist)
var kind := "patrol"               # "patrol" ou "sniper" (posté, longue portée)
var _touch_cd: float = 0.0         # délai entre deux dégâts de contact

const GUARD_FIRE_RATE := 1.1   # secondes entre deux tirs de garde
const MAX_HP := 2              # le garde encaisse 2 balles
var _fire_cd: float = 0.0
var hp: int = MAX_HP
var hit_flash: float = 0.0     # 0..1, pour le clignotement quand touché

var _state: int = State.PATROL
var _detect: float = 0.0
var _wp_index: int = 0
var _facing := Vector2.DOWN
var _last_known := Vector2.ZERO   # dernière position où le joueur a été vu
var _search_t := 0.0              # temps de fouille restant
var _look_t := 0.0                # minuterie pour "regarder autour"

@onready var _cone: Node2D = $VisionCone


func _ready() -> void:
	if patrol_points.size() > 0:
		# Démarre la ronde vers le premier point distinct.
		_wp_index = 0
	if kind == "sniper" and _cone != null:
		_cone.view_distance = 330.0      # longue portée
		_cone.view_angle_deg = 15.0      # cône étroit
	_update_cone_visual()


func _physics_process(delta: float) -> void:
	hit_flash = max(0.0, hit_flash - delta * 5.0)
	if not active or player == null:
		velocity = Vector2.ZERO
		return

	var sees_player: bool = _cone != null and _cone.can_see(player.global_position)

	# Mise à jour de la détection et de la mémoire.
	if sees_player:
		_detect = min(ALERT_THRESHOLD, _detect + DETECT_RISE * detect_mult * delta)
		if alarm != null and alarm.has_method("add_detection"):
			alarm.add_detection(ALARM_GAIN * alarm_gain_mult * delta)
		_last_known = player.global_position
		_search_t = SEARCH_TIME
	else:
		_detect = max(0.0, _detect - DETECT_FALL * delta)
		_search_t = max(0.0, _search_t - delta)

	# Alerte globale forcée par la jauge d'alarme.
	var global_alert: bool = alarm != null and "global_alert" in alarm and alarm.global_alert

	# Transitions d'état (du plus urgent au plus calme).
	if global_alert or _detect >= ALERT_THRESHOLD:
		_state = State.ALERT
	elif sees_player or _detect >= SUSPECT_THRESHOLD:
		_state = State.SUSPECT
	elif _search_t > 0.0:
		_state = State.SEARCH
	else:
		_state = State.PATROL

	match _state:
		State.PATROL:
			_do_patrol(delta)
		State.SUSPECT:
			_do_suspect(delta)
		State.SEARCH:
			_do_search(delta)
		State.ALERT:
			_do_alert(delta)

	# Riposte : en alerte, le garde tire sur le joueur s'il le voit.
	_fire_cd = max(0.0, _fire_cd - delta)
	if _state == State.ALERT and sees_player and bullet_system != null and _fire_cd <= 0.0:
		var aim := player.global_position - global_position
		bullet_system.spawn(global_position + aim.normalized() * 18.0, aim, false)
		_fire_cd = GUARD_FIRE_RATE * fire_mult

	move_and_slide()
	_aim_cone(delta)
	_update_cone_visual()


func _do_patrol(_delta: float) -> void:
	if patrol_points.size() == 0:
		velocity = Vector2.ZERO
		return
	var target := patrol_points[_wp_index]
	var to_target := target - global_position
	if to_target.length() <= WAYPOINT_REACHED:
		_wp_index = (_wp_index + 1) % patrol_points.size()
		target = patrol_points[_wp_index]
		to_target = target - global_position
	var dir := to_target.normalized()
	velocity = dir * PATROL_SPEED
	_facing = dir


func _do_suspect(_delta: float) -> void:
	# S'avance doucement vers le joueur en l'observant.
	var to_player := player.global_position - global_position
	_facing = to_player.normalized()
	velocity = _facing * SUSPECT_SPEED


## Fouille : fonce vers la dernière position connue, puis regarde autour.
func _do_search(delta: float) -> void:
	var to_target := _last_known - global_position
	if to_target.length() > WAYPOINT_REACHED * 2.0:
		# Rejoint le dernier point connu.
		_facing = to_target.normalized()
		velocity = _facing * SEARCH_SPEED
	else:
		# Sur place : balaie le regard pour chercher le joueur.
		velocity = Vector2.ZERO
		_look_t += delta
		_facing = Vector2.RIGHT.rotated(_look_t * 2.2)


func _do_alert(delta: float) -> void:
	var to_player := player.global_position - global_position
	_facing = to_player.normalized()
	velocity = _facing * CHASE_SPEED * chase_mult
	# Contact : en assist, on n'est PAS tué d'un coup — le garde inflige 1 PV
	# avec un délai (marge d'erreur). Sinon (hardcore), capture immédiate.
	_touch_cd = max(0.0, _touch_cd - delta)
	if to_player.length() <= CATCH_DISTANCE:
		if lethal_touch:
			if player.has_method("get_caught"):
				player.get_caught()
				player_caught.emit()
		elif _touch_cd <= 0.0 and player.has_method("take_damage"):
			player.take_damage(1)
			_touch_cd = 1.1


## Oriente progressivement le cône vers la direction de regard.
func _aim_cone(delta: float) -> void:
	if _cone == null or _facing.length() < 0.01:
		return
	var target_angle := _facing.angle()
	_cone.rotation = lerp_angle(_cone.rotation, target_angle, clamp(delta * 9.0, 0.0, 1.0))


func _update_cone_visual() -> void:
	if _cone != null and _cone.has_method("set_alert"):
		_cone.set_alert(_detect / ALERT_THRESHOLD, _state == State.ALERT)
	queue_redraw()


## Le garde a-t-il repéré quelque chose (enquête ou poursuite) ?
func is_engaged() -> bool:
	return _state != State.PATROL


# --- Accès pour le rendu isométrique ---

func get_facing() -> Vector2:
	return _facing

func get_alert_ratio() -> float:
	return _detect / ALERT_THRESHOLD

func is_alert() -> bool:
	return _state == State.ALERT

func get_view_distance() -> float:
	return _cone.view_distance if _cone != null else 0.0

func get_view_half_angle() -> float:
	return deg_to_rad(_cone.view_angle_deg) if _cone != null else 0.0


## Encaisse une balle. Retourne true si le garde est abattu (PV à 0).
## Être touché déclenche l'alerte immédiate (le garde riposte).
func hit() -> bool:
	hp -= 1
	hit_flash = 1.0
	_detect = ALERT_THRESHOLD
	_state = State.ALERT
	return hp <= 0


func stop() -> void:
	active = false
	velocity = Vector2.ZERO


func _draw() -> void:
	draw_circle(Vector2(0, 6), BODY_RADIUS, Color(0, 0, 0, 0.25))
	# Corps bleu.
	var body_color := Color(0.20, 0.35, 0.70)
	if _state == State.ALERT:
		body_color = Color(0.30, 0.45, 0.85)
	draw_circle(Vector2.ZERO, BODY_RADIUS, body_color)
	# Chapeau bleu foncé.
	var hat_offset := _facing.normalized() * 4.0 if _facing.length() > 0.01 else Vector2.ZERO
	draw_circle(hat_offset, BODY_RADIUS - 4.0, Color(0.12, 0.20, 0.45))
