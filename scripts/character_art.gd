class_name CharacterArt
extends RefCounted
## character_art.gd
## Rendu PARTAGÉ du cowboy / garde (dessiné en couches, directionnel, animé).
## Utilisé par la mission (iso_renderer) ET la ville (town) pour éviter toute
## duplication. On dessine sur n'importe quel CanvasItem `ci`.
##
## `base`  = position ÉCRAN des pieds (déjà projetée en iso).
## `f`     = direction de regard en espace ÉCRAN, normalisée (x: gauche/droite,
##           y: haut/bas). Le visage/bandana s'affichent selon l'orientation.

## Palette par défaut du héros (cowboy). Copier/adapter pour les PNJ.
static func hero_palette() -> Dictionary:
	return {
		"hat": Color(0.74, 0.62, 0.42), "hat_band": Color(0.55, 0.16, 0.12),
		"coat": Color(0.55, 0.36, 0.18), "coat_dark": Color(0.42, 0.27, 0.13),
		"shirt": Color(0.82, 0.46, 0.20), "pants": Color(0.32, 0.26, 0.20),
		"skin": Color(0.90, 0.69, 0.50), "bandana": Color(0.86, 0.22, 0.18),
		"belt": Color(0.26, 0.16, 0.09), "buckle": Color(0.95, 0.80, 0.32),
		"boots": Color(0.30, 0.18, 0.10), "hair": Color(0.25, 0.16, 0.09),
	}


static func draw_person(ci: CanvasItem, base: Vector2, f: Vector2, pal: Dictionary,
		is_guard: bool, alert: bool, walk: float, recoil: float, flash: float) -> void:
	var side := 1.0 if f.x >= 0.0 else -1.0
	if absf(f.x) < 0.12:
		side = 1.0
	var facing_up := f.y < -0.30
	var facing_down := f.y > 0.20

	var coat: Color = (pal["coat"] as Color).lerp(Color.WHITE, flash * 0.7)
	var coat_dark: Color = (pal["coat_dark"] as Color).lerp(Color.WHITE, flash * 0.7)
	var shirt: Color = (pal["shirt"] as Color).lerp(Color.WHITE, flash * 0.7)

	var sw := sin(walk) * 3.2
	var bob := absf(sin(walk)) * -1.6
	var hip := base + Vector2(0, -17.0 + bob)
	var shoulder := base + Vector2(0, -32.0 + bob)

	ci.draw_colored_polygon(_ellipse(base + Vector2(1, 1), 13.0, 6.0), Color(0, 0, 0, 0.25))

	var footL := base + Vector2(-5 - sw, -1)
	var footR := base + Vector2(5 + sw, -1)
	ci.draw_line(hip + Vector2(-4, 0), footL, pal["pants"], 6.0)
	ci.draw_line(hip + Vector2(4, 0), footR, pal["pants"], 6.0)
	_boot(ci, footL, side, pal["boots"])
	_boot(ci, footR, side, pal["boots"])

	var knee := base.y - 7.0 + bob * 0.4
	ci.draw_colored_polygon(PackedVector2Array([
		hip + Vector2(-7, 0), Vector2(base.x - 10 - sw * 0.4, knee),
		Vector2(base.x + 10 + sw * 0.4, knee), hip + Vector2(7, 0)]), coat_dark)

	_capsule(ci, hip + Vector2(0, -1), shoulder, 11.0, shirt)
	ci.draw_colored_polygon(PackedVector2Array([
		shoulder + Vector2(-9, 1), shoulder + Vector2(-1, 2),
		hip + Vector2(-2, 1), hip + Vector2(-9, -1)]), coat)
	ci.draw_colored_polygon(PackedVector2Array([
		shoulder + Vector2(9, 1), shoulder + Vector2(1, 2),
		hip + Vector2(2, 1), hip + Vector2(9, -1)]), coat.darkened(0.06))

	ci.draw_line(hip + Vector2(-9, 1), hip + Vector2(9, 1), pal["belt"], 4.0)
	ci.draw_rect(Rect2(hip + Vector2(-3, -1), Vector2(6, 4)), pal["buckle"])
	ci.draw_colored_polygon(_ellipse(hip + Vector2(8 * -side, 4), 3.5, 5.0),
			(pal["belt"] as Color).darkened(0.1))

	if is_guard:
		_star(ci, shoulder + Vector2(-4.0 * side, 6.0), 3.4,
				Color(1.0, 0.92, 0.4) if alert else Color(0.85, 0.78, 0.35))

	var gun_dir := Vector2(side, -0.12 if not facing_up else -0.45).normalized()
	var reach := 14.0 - recoil * 4.5
	var hand := shoulder + gun_dir * reach + Vector2(0, 5)
	ci.draw_line(shoulder + Vector2(-side * 5, 2), shoulder + Vector2(-side * 8, 8), coat.darkened(0.08), 4.5)
	ci.draw_line(shoulder + Vector2(side * 4, 3), hand, shirt, 4.5)
	ci.draw_line(hand, hand + gun_dir * 9.0, Color(0.16, 0.16, 0.19), 3.5)
	ci.draw_line(hand, hand + Vector2(0, 5), Color(0.10, 0.08, 0.06), 3.5)
	ci.draw_circle(hand + gun_dir * 9.0, 1.4, Color(0.75, 0.76, 0.8))

	var head := shoulder + Vector2(side * 1.0, -8.0)
	ci.draw_line(shoulder, head + Vector2(0, 4), pal["skin"], 4.0)
	if not facing_up:
		ci.draw_colored_polygon(PackedVector2Array([
			shoulder + Vector2(-5, 1), shoulder + Vector2(5, 1),
			shoulder + Vector2(0, 6)]), pal["bandana"])
	ci.draw_circle(head, 6.0, pal["skin"])
	if not facing_up:
		if facing_down:
			ci.draw_circle(head + Vector2(-2.2, -1.0), 0.9, Color(0.1, 0.08, 0.07))
			ci.draw_circle(head + Vector2(2.2, -1.0), 0.9, Color(0.1, 0.08, 0.07))
			ci.draw_line(head + Vector2(-2.5, 2.2), head + Vector2(2.5, 2.2), pal["hair"], 1.6)
		else:
			ci.draw_circle(head + Vector2(side * 1.5, -1.0), 0.9, Color(0.1, 0.08, 0.07))
			ci.draw_line(head + Vector2(side * 1.0, 2.2), head + Vector2(side * 3.0, 2.2), pal["hair"], 1.6)
	else:
		ci.draw_arc(head, 5.0, 0.2, PI - 0.2, 8, pal["hair"], 2.2)

	_hat(ci, head + Vector2(0, -3.5), side, facing_up, pal)


static func _boot(ci: CanvasItem, p: Vector2, side: float, col: Color) -> void:
	ci.draw_circle(p, 3.0, col)
	ci.draw_rect(Rect2(p + Vector2(min(0.0, side * 3.0), 0.0), Vector2(absf(side) * 3.0 + 3.0, 2.4)), col)


static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var rad := r if i % 2 == 0 else r * 0.45
		var a := -PI / 2 + PI * float(i) / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	ci.draw_colored_polygon(pts, col)


static func _hat(ci: CanvasItem, center: Vector2, side: float, facing_up: bool, pal: Dictionary) -> void:
	var hat: Color = pal["hat"]
	var brim_c := center + Vector2(side * 0.8, 1.0)
	ci.draw_colored_polygon(_ellipse(brim_c, 13.0, 4.2), hat.darkened(0.12))
	ci.draw_polyline(_closed(_ellipse(brim_c, 13.0, 4.2)), hat.darkened(0.28), 1.0)
	var cx := center.x + side * 0.8
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 6.5, center.y + 1.0), Vector2(cx - 5.0, center.y - 7.0),
		Vector2(cx + 5.0, center.y - 7.0), Vector2(cx + 6.5, center.y + 1.0)]), hat)
	ci.draw_colored_polygon(_ellipse(Vector2(cx, center.y - 7.0), 5.0, 1.8), hat.lightened(0.06))
	ci.draw_line(Vector2(cx - 6.2, center.y - 0.2), Vector2(cx + 6.2, center.y - 0.2), pal["hat_band"], 2.6)
	if not facing_up:
		ci.draw_line(Vector2(cx - 3.0, center.y - 5.5), Vector2(cx + 1.0, center.y - 6.0),
				hat.lightened(0.22), 1.2)


static func _capsule(ci: CanvasItem, a: Vector2, b: Vector2, width: float, col: Color) -> void:
	ci.draw_line(a, b, col, width)
	ci.draw_circle(a, width * 0.5, col)
	ci.draw_circle(b, width * 0.5, col)


static func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(18):
		var t := TAU * float(i) / 18.0
		pts.append(center + Vector2(cos(t) * rx, sin(t) * ry))
	return pts


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var c := poly.duplicate()
	if c.size() > 0:
		c.append(c[0])
	return c
