extends Control
## ui_backdrop.gd
## Décor de fond peint pour les menus (coucher de soleil far-west) : ciel dégradé,
## soleil, mesas en silhouette, sol. L'ambiance change selon `mood`
## (menu / win / lose / shop). Aucun asset requis — tout en _draw().

@export var mood := "menu"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := size if size.x > 1.0 else get_viewport_rect().size
	var top: Color
	var horizon: Color
	var ground: Color
	var sun: Color
	match mood:
		"win":
			top = Color(0.20, 0.12, 0.28); horizon = Color(1.0, 0.72, 0.32)
			ground = Color(0.36, 0.23, 0.13); sun = Color(1.0, 0.93, 0.6)
		"lose":
			top = Color(0.09, 0.05, 0.09); horizon = Color(0.55, 0.18, 0.16)
			ground = Color(0.14, 0.08, 0.07); sun = Color(0.75, 0.28, 0.20)
		"shop":
			top = Color(0.15, 0.10, 0.22); horizon = Color(0.95, 0.58, 0.30)
			ground = Color(0.30, 0.20, 0.12); sun = Color(1.0, 0.85, 0.5)
		_:
			top = Color(0.22, 0.13, 0.30); horizon = Color(1.0, 0.62, 0.28)
			ground = Color(0.33, 0.20, 0.12); sun = Color(1.0, 0.88, 0.5)

	var hy := s.y * 0.62
	# Ciel dégradé (bandes lerp).
	var strips := 48
	for i in range(strips):
		var t := float(i) / strips
		var c := top.lerp(horizon, pow(t, 1.4))
		draw_rect(Rect2(0, t * hy, s.x, hy / strips + 1.0), c)
	# Étoiles dans le haut sombre.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in range(40):
		var p := Vector2(rng.randf() * s.x, rng.randf() * hy * 0.5)
		draw_circle(p, rng.randf_range(0.6, 1.4), Color(1, 1, 1, rng.randf_range(0.1, 0.4)))
	# Soleil + halo.
	var sc := Vector2(s.x * 0.5, hy * 0.74)
	for g in range(7):
		draw_circle(sc, 90.0 - g * 9.0, Color(sun.r, sun.g, sun.b, 0.05))
	draw_circle(sc, 46.0, sun)
	draw_circle(sc, 46.0, horizon.darkened(0.1), false, 2.0)
	# Mesas en silhouette.
	_mesa(Vector2(s.x * 0.17, hy), 240.0, 95.0, ground.lerp(top, 0.35))
	_mesa(Vector2(s.x * 0.82, hy), 320.0, 135.0, ground.lerp(top, 0.18))
	_mesa(Vector2(s.x * 0.52, hy), 180.0, 70.0, ground.lerp(top, 0.45))
	# Sol.
	draw_rect(Rect2(0, hy, s.x, s.y - hy), ground)
	draw_rect(Rect2(0, hy, s.x, 3.0), horizon.darkened(0.15))
	for i in range(60):
		var gx := rng.randf() * s.x
		var gy := hy + rng.randf() * (s.y - hy)
		draw_circle(Vector2(gx, gy), rng.randf_range(1.0, 2.4), ground.darkened(0.25))
	# Vignette d'ambiance.
	draw_rect(Rect2(0, 0, s.x, s.y), Color(0, 0, 0, 0.22), false, 60.0)


func _mesa(base: Vector2, w: float, h: float, col: Color) -> void:
	var hw := w * 0.5
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(-hw, 0),
		base + Vector2(-hw * 0.72, -h),
		base + Vector2(hw * 0.62, -h),
		base + Vector2(hw, 0),
	]), col)
