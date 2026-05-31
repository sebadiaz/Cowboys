extends Area2D
## loot_system.gd
## Sac de butin collectable. Se ramasse au contact du joueur (style arcade)
## et signale sa valeur. Dessiné en jaune avec un symbole "$".

signal collected(value: int)

@export var value: int = 150
const RADIUS := 13.0

var _taken := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _taken:
		return
	if body.is_in_group("player"):
		_taken = true
		collected.emit(value)
		queue_free()


func _draw() -> void:
	draw_circle(Vector2(0, 5), RADIUS, Color(0, 0, 0, 0.22))
	# Sac jaune.
	draw_circle(Vector2.ZERO, RADIUS, Color(0.95, 0.80, 0.15))
	draw_circle(Vector2(0, -RADIUS * 0.6), RADIUS * 0.45, Color(0.80, 0.66, 0.10))
	# Symbole "$".
	var font := ThemeDB.fallback_font
	var size := 18
	var text := "$"
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(-w * 0.5, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.25, 0.18, 0.0))
