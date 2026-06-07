extends Area2D
## safe.gd
## Coffre interactif. Le joueur reste à proximité et maintient l'interaction
## (E / bouton tactile) pour remplir une barre de progression. Une fois plein,
## le coffre est ouvert et libère sa récompense.

signal opened(value: int)

@export var value: int = 500
@export var open_time: float = 2.5
const HALF := Vector2(26, 20)

var _player_in_range := false
var _progress: float = 0.0
var _is_open := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _is_open:
		return
	if _player_in_range and InputManager.is_interact_held():
		_progress = min(1.0, _progress + delta / max(0.1, open_time))
		queue_redraw()
		if _progress >= 1.0:
			_open()


func _open() -> void:
	_is_open = true
	opened.emit(value)
	queue_redraw()


## Ouverture instantanée (dynamite).
func force_open() -> void:
	if not _is_open:
		_open()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		queue_redraw()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		queue_redraw()


func _draw() -> void:
	# Ombre puis corps du coffre (gris), porte plus claire quand ouvert.
	draw_rect(Rect2(-HALF + Vector2(3, 5), HALF * 2.0), Color(0, 0, 0, 0.22))
	var body_col := Color(0.35, 0.35, 0.38) if not _is_open else Color(0.45, 0.40, 0.25)
	draw_rect(Rect2(-HALF, HALF * 2.0), body_col)
	draw_rect(Rect2(-HALF, HALF * 2.0), Color(0.15, 0.15, 0.17), false, 3.0)
	# Cadran.
	draw_circle(Vector2(0, 0), 6.0, Color(0.7, 0.7, 0.2) if _is_open else Color(0.7, 0.7, 0.75))

	if _is_open:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-HALF.x, -HALF.y - 6), "OUVERT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.9, 0.4))
		return

	# Barre de progression au-dessus du coffre quand on l'ouvre.
	if _player_in_range or _progress > 0.0:
		var bar_w := HALF.x * 2.0
		var bar_top := -HALF.y - 14.0
		draw_rect(Rect2(-HALF.x, bar_top, bar_w, 7), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-HALF.x, bar_top, bar_w * _progress, 7), Color(0.95, 0.8, 0.2))
		if _progress <= 0.0:
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(-HALF.x, bar_top - 4), "Maintiens E", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
