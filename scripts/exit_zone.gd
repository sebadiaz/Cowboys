extends Area2D
## exit_zone.gd
## Zone de sortie verte. Quand le joueur y entre, signale qu'il tente de sortir.
## La réussite/échec est décidée par mission_manager (selon le butin).

signal player_entered()

const HALF := Vector2(46, 46)

var _armed := true


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _armed and body.is_in_group("player"):
		_armed = false
		player_entered.emit()


## Réarme la sortie (ex. le joueur est entré sans butin).
func rearm() -> void:
	_armed = true


func _draw() -> void:
	draw_rect(Rect2(-HALF, HALF * 2.0), Color(0.20, 0.65, 0.25, 0.55))
	draw_rect(Rect2(-HALF, HALF * 2.0), Color(0.15, 0.5, 0.2), false, 3.0)
	var font := ThemeDB.fallback_font
	var text := "SORTIE"
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(font, Vector2(-w * 0.5, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 1.0, 0.9))
