extends Control
## hud_gfx.gd
## Dessin "premium" du HUD de mission (cuir + laiton + or) : cœurs de PV, barillet
## six-coups pour les munitions, jauge d'alarme stylée, magot et butin. Tout est
## peint dans _draw() pour un rendu net et cohérent ; les valeurs sont poussées
## par hud_controller via les setters publics. Aucun asset requis.

var hp := 3
var max_hp := 3
var ammo := 6
var cap := 6
var reloading := false
var reload_ratio := 1.0
var loot_bags := 0
var loot_value := 0
var money := 0
var alarm := 0.0          # 0..1
var global_alert := false
var objective := ""
var state_alert := false
var _t := 0.0

const LEATHER := Color(0.16, 0.10, 0.06, 0.82)
const LEATHER2 := Color(0.10, 0.06, 0.04, 0.88)
const GOLD := Color(0.92, 0.74, 0.30)
const INK := Color(0.04, 0.03, 0.02)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()   # léger pulse/animation (barillet, alarme)


func _draw() -> void:
	var w := size.x if size.x > 1.0 else get_viewport_rect().size.x
	var font := ThemeDB.fallback_font
	# --- Bandeau cuir ---
	var bh := 70.0
	_panel(Rect2(0, 0, w, bh), LEATHER, Color(0, 0, 0, 0), 0.0)
	draw_rect(Rect2(0, bh - 3.0, w, 3.0), GOLD)
	draw_rect(Rect2(0, bh, w, 2.0), Color(0, 0, 0, 0.35))

	# --- Gauche : cœurs (PV) + barillet (munitions) ---
	# Plafond d'affichage : au-delà de 10 cœurs on passe en numérique
	# (sécurité : un max_hp énorme dessinerait des milliers de primitives).
	var hx := 18.0
	var shown := mini(max_hp, 10)
	for i in range(shown):
		_heart(Vector2(hx + i * 22.0, 18.0), 8.0, i < hp)
	if max_hp > 10:
		_text(font, Vector2(hx + shown * 22.0 + 6.0, 6.0), "%d/%d" % [hp, max_hp], 15,
				Color(0.95, 0.6, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
	_cylinder(Vector2(20.0, 44.0))

	# --- Droite : magot + butin ---
	_text(font, Vector2(w - 18.0, 10.0), "%d $" % money, 22, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_coin(Vector2(w - 18.0 - _text_w(font, "%d $" % money, 22) - 14.0, 20.0), 7.0)
	var loot_s := "%d sac%s · %d $" % [loot_bags, "s" if loot_bags > 1 else "", loot_value]
	_text(font, Vector2(w - 18.0, 40.0), loot_s, 15, Color(0.95, 0.9, 0.78), HORIZONTAL_ALIGNMENT_RIGHT)

	# --- Centre : objectif (réduit pour tenir) + jauge d'alarme + état ---
	var cx := w * 0.5
	var avail := maxf(180.0, w - 460.0)
	var osize := 17
	while osize > 11 and _text_w(font, objective, osize) > avail:
		osize -= 1
	_text(font, Vector2(cx, 6.0), objective, osize, Color(1, 0.97, 0.88), HORIZONTAL_ALIGNMENT_CENTER)
	_alarm_gauge(Rect2(cx - 150.0, 38.0, 240.0, 18.0))
	_state_badge(Vector2(cx + 104.0, 38.0))


# --- Widgets ---

func _heart(c: Vector2, r: float, filled: bool) -> void:
	var col := Color(0.90, 0.18, 0.20) if filled else Color(0.28, 0.16, 0.16)
	if filled:
		var beat := 1.0 + 0.06 * sin(_t * 4.0 + c.x)
		r *= beat
	# Deux bosses + pointe.
	draw_circle(c + Vector2(-r * 0.5, -r * 0.35), r * 0.62, col)
	draw_circle(c + Vector2(r * 0.5, -r * 0.35), r * 0.62, col)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 1.05, -r * 0.05), c + Vector2(r * 1.05, -r * 0.05), c + Vector2(0, r * 1.15)]), col)
	if filled:
		draw_circle(c + Vector2(-r * 0.55, -r * 0.5), r * 0.18, Color(1, 1, 1, 0.55))   # reflet


func _cylinder(origin: Vector2) -> void:
	# Barillet six-coups : 6 alvéoles autour d'un moyeu, qui tourne en rechargeant.
	var cc := origin + Vector2(13.0, 12.0)
	draw_circle(cc, 15.0, Color(0.20, 0.15, 0.10, 0.9))
	draw_circle(cc, 15.0, GOLD if reloading else Color(0.45, 0.34, 0.2), false, 2.0)
	var spin := _t * 7.0 if reloading else 0.0
	var sweep := fmod(_t * 1.8, 1.0)   # balayage de remplissage pendant la recharge
	for i in range(cap):
		var a := -PI / 2.0 + TAU * float(i) / float(cap) + spin
		var p := cc + Vector2.RIGHT.rotated(a) * 9.0
		var loaded := i < ammo
		if reloading:
			loaded = float(i) / float(cap) <= sweep
		draw_circle(p, 3.2, Color(0.92, 0.78, 0.32) if loaded else Color(0.12, 0.09, 0.07))
		draw_circle(p, 3.2, Color(0, 0, 0, 0.5), false, 1.0)
	draw_circle(cc, 2.4, Color(0.5, 0.4, 0.25))
	var font := ThemeDB.fallback_font
	var txt := "RECH…" if reloading else "%d/%d" % [ammo, cap]
	_text(font, Vector2(origin + Vector2(34.0, 4.0)), txt, 15,
		Color(1.0, 0.82, 0.3) if (reloading or ammo == 0) else Color(0.95, 0.92, 0.82), HORIZONTAL_ALIGNMENT_LEFT)


func _coin(c: Vector2, r: float) -> void:
	draw_circle(c, r, GOLD)
	draw_circle(c, r, Color(0.6, 0.45, 0.15), false, 1.5)
	draw_circle(c, r * 0.5, Color(1, 0.9, 0.5, 0.8))


func _alarm_gauge(r: Rect2) -> void:
	_panel(r, Color(0.05, 0.04, 0.03, 0.9), Color(0.5, 0.4, 0.25), 1.5)
	var col := Color(0.4, 0.85, 0.4).lerp(Color(1.0, 0.2, 0.15), alarm)
	if global_alert:
		col = Color(1.0, 0.2, 0.15)
	var inner := Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4.0) * alarm, r.size.y - 4.0))
	draw_rect(inner, col)
	# Reflet + crête animée quand ça monte.
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.4)), Color(1, 1, 1, 0.18))
	# Graduations.
	for i in range(1, 4):
		var x := r.position.x + r.size.x * 0.25 * i
		draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(0, 0, 0, 0.35), 1.0)
	var font := ThemeDB.fallback_font
	var pulse := 0.6 + 0.4 * sin(_t * (4.0 + alarm * 6.0)) if alarm > 0.3 else 1.0
	var lbl := "⚠ ALERTE GÉNÉRALE" if global_alert else "ALARME"
	var lc := Color(1.0, 0.4, 0.3, pulse) if (global_alert or alarm > 0.6) else Color(0.9, 0.85, 0.7)
	_text(font, Vector2(r.get_center().x, r.position.y - 16.0), lbl, 12, lc, HORIZONTAL_ALIGNMENT_CENTER)


func _state_badge(pos: Vector2) -> void:
	var txt := "ALERTE" if state_alert else "DISCRET"
	var col := Color(1.0, 0.28, 0.22) if state_alert else Color(0.45, 0.85, 0.45)
	var font := ThemeDB.fallback_font
	var tw := _text_w(font, txt, 13) + 16.0
	var r := Rect2(pos.x, pos.y, tw, 18.0)
	_panel(r, Color(col.r, col.g, col.b, 0.22), col, 1.5)
	if state_alert:
		# Petit point clignotant.
		draw_circle(r.position + Vector2(9, 9), 3.0, Color(1, 0.3, 0.2, 0.5 + 0.5 * sin(_t * 8.0)))
	_text(font, Vector2(r.get_center().x + (4 if state_alert else 0), r.position.y + 2.0), txt, 13, col, HORIZONTAL_ALIGNMENT_CENTER)


# --- Primitives ---

func _panel(r: Rect2, fill: Color, border: Color, bw: float) -> void:
	draw_rect(r, fill)
	if bw > 0.0 and border.a > 0.0:
		draw_rect(r, border, false, bw)


func _text(font: Font, pos: Vector2, s: String, size_px: int, col: Color, align: int) -> void:
	if s == "":
		return
	var w := _text_w(font, s, size_px)
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	var base := Vector2(x, pos.y + size_px)
	# Contour encre (4 directions) + texte.
	for o in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
		draw_string(font, base + o, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, INK)
	draw_string(font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)


func _text_w(font: Font, s: String, size_px: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
