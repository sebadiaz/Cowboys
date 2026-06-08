extends Node2D
## top_down_renderer.gd
## Rendu de mission en VRAIE VUE DE DESSUS avec des SPRITES (pack CC0 Kenney
## "Tiny Town"). Remplace le rendu iso procédural. Tout le reste (physique, IA,
## visée souris, balles, effets, cônes) fonctionne tel quel grâce à `Iso.top_down`
## (projection identité). Les entités restent invisibles ; ce noeud les dessine.

const SHEET_PATH := "res://assets/sprites/tiny_town.png"      # décor (sol, murs, props)
const CHARS_PATH := "res://assets/sprites/tiny_dungeon.png"   # personnages (cast distinct)
const TILE := 16          # taille native d'une tuile (px)
const COLS := 12          # colonnes du sheet

# Cast (sheet Tiny Dungeon) — silhouettes distinctes par camp.
const C_PLAYER := 84      # figure à chapeau -> cowboy (teinté tan)
const C_GUARD := 96       # chevalier casqué -> shérif/garde (armure)
const C_SNIPER := 97      # chevalier sombre -> tireur posté
const C_ALLY := 112       # rôdeur -> hors-la-loi de la bande
const C_HOST := 99        # civil(e) -> otage
const C_NPC := 88         # villageois -> commis de banque

# Index de tuiles (cf. cartographie du sheet).
const T_SAND := 40
const T_SAND2 := 25
const T_GRASS := 0
const T_WALL := 76        # mur pierre
const T_WOOD := 72        # bois (comptoir / plancher)
const T_FENCE := 80       # barrière horizontale
const T_CHEST := 107      # coffre / caisse
const T_LOG := 106        # rondin (tonneau)
const T_COIN := 93        # pièce d'or (butin)
const T_GOLD := 94        # pot d'or (tas)
const T_SIGN := 83        # panneau (affiche)
const T_TREE := 3
const T_DOOR := 74        # porte (sortie)
const T_BOMB := 105       # dynamite
const T_CHAR := 104       # personnage

# Données fournies par mission_manager (mêmes noms que l'ancien renderer).
var floor_rect: Rect2
var walls: Array[Dictionary] = []
var props: Array = []
var player: Node2D
var guards: Array = []
var loot: Array = []
var safe: Node = null
var exit_zone: Node = null
var bullets: Node = null
var biome := "desert"
var dynamite: Node = null
var hostages: Array = []
var safes2: Array = []
var allies: Array = []
var coach_mode := false
var fx: Node2D = null
var focus := 1.0
var focus_active := false

var _sheet: Texture2D
var _chars: Texture2D
var _floor_atlas: AtlasTexture
var _wall_atlas: AtlasTexture
var _wood_atlas: AtlasTexture
var _corpses: Array[Dictionary] = []
var _cam := Vector2.ZERO


func add_corpse(world_pos: Vector2, facing: Vector2, dir := Vector2.ZERO) -> void:
	_corpses.append({"pos": world_pos, "facing": facing, "t": 0.0, "dir": dir})


func setup() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sheet = load(SHEET_PATH)
	_chars = load(CHARS_PATH)
	_floor_atlas = _atlas(T_SAND if biome != "plains" else T_GRASS)
	_wall_atlas = _atlas(T_WALL)
	_wood_atlas = _atlas(T_WOOD)
	_apply_zoom()
	_cam = _camera_target()
	position = _cam
	queue_redraw()


func refit() -> Vector2:
	_apply_zoom()
	_cam = _camera_target()
	position = _cam
	queue_redraw()
	return _cam


func _atlas(idx: int) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = _sheet
	a.region = _region(idx)
	return a


func _region(idx: int) -> Rect2:
	return Rect2((idx % COLS) * TILE, (idx / COLS) * TILE, TILE, TILE)


func _apply_zoom() -> void:
	var vp := get_viewport_rect().size
	var z := clampf(minf(vp.x, vp.y) / 430.0, 1.4, 3.0)
	scale = Vector2(z, z)


func _camera_target() -> Vector2:
	var vp := get_viewport_rect().size
	var s: float = scale.x
	var focus_w := player.global_position if is_instance_valid(player) else floor_rect.get_center()
	var t := vp * 0.5 - focus_w * s
	t.x = _clamp_axis(t.x, s, vp.x, floor_rect.position.x, floor_rect.end.x)
	t.y = _clamp_axis(t.y, s, vp.y, floor_rect.position.y, floor_rect.end.y)
	return t


func _clamp_axis(t: float, s: float, screen: float, bmin: float, bmax: float) -> float:
	var lo := screen - s * bmax
	var hi := -s * bmin
	if lo > hi:
		return screen * 0.5 - s * (bmin + bmax) * 0.5
	return clampf(t, lo, hi)


func _process(delta: float) -> void:
	var live: Array[Dictionary] = []
	for c in _corpses:
		c["t"] += delta
		if c["t"] < 1.2:
			live.append(c)
	_corpses = live
	_cam = _cam.lerp(_camera_target(), clampf(delta * 9.0, 0.0, 1.0))
	var shake := Vector2.ZERO
	if fx != null and fx.has_method("get_shake_offset"):
		shake = fx.get_shake_offset()
	position = _cam + shake
	queue_redraw()


func _draw() -> void:
	Iso.top_down = true          # vue de dessus : projection identité
	_draw_floor()
	_draw_walls()
	# Sortie (au sol).
	if is_instance_valid(exit_zone):
		var ep: Vector2 = exit_zone.global_position
		draw_rect(Rect2(ep - Vector2(26, 26), Vector2(52, 52)), Color(0.25, 0.7, 0.3, 0.55))
		draw_rect(Rect2(ep - Vector2(26, 26), Vector2(52, 52)), Color(0.5, 1.0, 0.55), false, 2.0)
		_spr(T_DOOR, ep, 30, 30, Color.WHITE, 6.0)
		_label_c("SORTIE", ep + Vector2(0, -30), 12, Color(0.9, 1, 0.9))
	_draw_cones()

	# Tout ce qui est "objet/perso", trié par profondeur Y.
	var items: Array[Dictionary] = []
	for p in props:
		if p is Array and p.size() >= 3:
			items.append({"y": float(p[2]), "k": "prop", "o": p})
	for c in _corpses:
		items.append({"y": c["pos"].y - 1.0, "k": "corpse", "o": c})
	if is_instance_valid(safe):
		items.append({"y": safe.global_position.y, "k": "safe"})
	for sb in safes2:
		if is_instance_valid(sb):
			items.append({"y": sb.global_position.y, "k": "sbox", "o": sb})
	for b in loot:
		if is_instance_valid(b):
			items.append({"y": b.global_position.y, "k": "loot", "o": b})
	for h in hostages:
		if is_instance_valid(h):
			items.append({"y": h.global_position.y, "k": "host", "o": h})
	if is_instance_valid(dynamite) and dynamite.visible:
		items.append({"y": dynamite.global_position.y, "k": "dyn"})
	for a in allies:
		if is_instance_valid(a):
			items.append({"y": a.global_position.y, "k": "ally", "o": a})
	for g in guards:
		if is_instance_valid(g):
			items.append({"y": g.global_position.y, "k": "guard", "o": g})
	if is_instance_valid(player):
		items.append({"y": player.global_position.y, "k": "me"})
	items.sort_custom(func(a, b): return a["y"] < b["y"])

	for it in items:
		match it["k"]:
			"prop": _draw_prop(it["o"])
			"corpse": _draw_corpse(it["o"])
			"safe": _draw_safe()
			"sbox":
				_spr(T_CHEST, it["o"].global_position, 30, 30, Color(0.8, 0.85, 0.95))
				_safe_bar(it["o"], "COFFRE")
			"loot": _shadow_spr(T_COIN, it["o"].global_position, 18, 18, 1.0)
			"host":
				_char(it["o"].global_position, Vector2.DOWN, Color(1.1, 1.0, 0.85), "host")
				_label_c("AIDE !", it["o"].global_position + Vector2(0, -34), 11, Color(1, 0.85, 0.4))
			"dyn": _shadow_spr(T_BOMB, dynamite.global_position, 20, 20, 1.0)
			"ally": _char(it["o"].global_position, it["o"].get_facing(), Color(0.78, 1.05, 0.8), "ally")
			"guard":
				var gk := "sniper" if str(it["o"].get("kind")) == "sniper" else "guard"
				var gmod := Color(0.85, 0.9, 1.2) if it["o"].is_alert() else Color(0.92, 0.95, 1.08)
				if gk == "sniper":
					gmod = Color(0.6, 0.62, 0.72)   # manteau sombre du tireur
				_char(it["o"].global_position, it["o"].get_facing(), gmod, gk)
			"me": _char(player.global_position, player.facing, Color(1.4, 0.95, 0.4), "me")

	_draw_bullets()
	_draw_focus()
	Iso.top_down = true


# --- Sol & murs ---

func _draw_floor() -> void:
	draw_texture_rect(_floor_atlas, floor_rect, true)
	draw_rect(floor_rect, Color(0, 0, 0, 0.10), false, 2.0)


func _draw_walls() -> void:
	for w in walls:
		var r: Rect2 = w["rect"]
		var low: bool = w.get("low", false)
		var at := _wood_atlas if low else _wall_atlas
		draw_texture_rect(at, r, true)
		draw_rect(r, Color(0, 0, 0, 0.30), false, 1.5)
		if low:
			# Liseré clair sur le dessus du comptoir.
			draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(0.85, 0.7, 0.4, 0.7))


# --- Props ---

func _draw_prop(p: Array) -> void:
	var t := str(p[0])
	var pos := Vector2(float(p[1]), float(p[2]))
	match t:
		"barrel": _shadow_spr(T_LOG, pos, 22, 22, 0.0)
		"crate", "shelf", "desk": _shadow_spr(T_CHEST, pos, 24, 24, 0.0)
		"plant": _shadow_spr(T_TREE, pos, 26, 30, 4.0)
		"money", "goldpile": _shadow_spr(T_GOLD, pos, 20, 20, 0.0)
		"poster", "painting": _spr(T_SIGN, pos, 22, 22, Color.WHITE, 2.0)
		"clerk": _char(pos, Vector2.DOWN, Color(1.0, 0.95, 0.8), "npc")
		"coach": _spr(T_CHEST, pos, 56, 40, Color(0.75, 0.55, 0.35))
		"chair", "lamp", "chandelier": pass
		_: _shadow_spr(T_CHEST, pos, 22, 22, 0.0)


func _draw_safe() -> void:
	var pos: Vector2 = safe.global_position
	_shadow_spr(T_CHEST, pos, 40, 40, 0.0)
	_safe_bar(safe, "DILIGENCE" if coach_mode else "COFFRE")


func _safe_bar(node: Node, label: String) -> void:
	var head: Vector2 = node.global_position + Vector2(0, -34.0)
	if node._is_open:
		_label_c("OUVERT", head, 12, Color(0.95, 0.9, 0.4))
		return
	var prog: float = node._progress
	if node._player_in_range or prog > 0.0:
		var w := 44.0
		draw_rect(Rect2(head + Vector2(-w * 0.5, -3), Vector2(w, 6)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(head + Vector2(-w * 0.5, -3), Vector2(w * prog, 6)), Color(0.95, 0.8, 0.2))
		if prog <= 0.01:
			_label_c("Maintiens E", head + Vector2(0, -8), 11, Color(1, 1, 1))


# --- Personnages ---

func _char(pos: Vector2, facing: Vector2, mod: Color, kind: String) -> void:
	# Ombre de contact.
	draw_colored_polygon(_ellipse(pos + Vector2(0, 2), 11, 5), Color(0, 0, 0, 0.28))
	# Sprite distinct par camp (sheet Tiny Dungeon), légèrement teinté.
	var idx: int = _char_idx(kind)
	var w := 30.0 if kind == "me" else 28.0
	draw_texture_rect_region(_chars, Rect2(pos.x - w * 0.5, pos.y - w + 2.0, w, w), _region(idx), mod)
	# Pastille de camp au-dessus (lisibilité instantanée).
	var c: Color
	match kind:
		"me": c = Color(1.0, 0.85, 0.25)
		"guard": c = Color(0.35, 0.55, 1.0)
		"ally": c = Color(0.4, 0.9, 0.45)
		"host": c = Color(1.0, 0.8, 0.3)
		_: c = Color(0.8, 0.8, 0.8)
	draw_circle(pos + Vector2(0, -w + 1.0), 2.6, c)


## Tuile de personnage (sheet Tiny Dungeon) selon le camp.
func _char_idx(kind: String) -> int:
	match kind:
		"me": return C_PLAYER
		"guard": return C_GUARD
		"sniper": return C_SNIPER
		"ally": return C_ALLY
		"host": return C_HOST
		_: return C_NPC


func _draw_corpse(c: Dictionary) -> void:
	var t: float = clampf(c["t"] / 1.2, 0.0, 1.0)
	var pos: Vector2 = c["pos"]
	var dvec: Vector2 = c.get("dir", Vector2.ZERO)
	pos += dvec.normalized() * ((1.0 - (1.0 - t) * (1.0 - t)) * 22.0) if dvec.length() > 0.01 else Vector2.ZERO
	draw_colored_polygon(_ellipse(pos + Vector2(0, 2), 12, 5), Color(0, 0, 0, 0.18 * (1.0 - t)))
	# Garde couché (sprite chevalier transposé) qui s'efface dans une mare sombre.
	var region := _region(C_GUARD)
	draw_texture_rect_region(_chars, Rect2(pos + Vector2(-13, -8), Vector2(26, 16)), region,
			Color(0.55, 0.18, 0.16, 1.0 - t), true)


# --- Cônes de vision (raycast contre les murs) ---

func _draw_cones() -> void:
	var space := get_world_2d().direct_space_state
	for g in guards:
		if not is_instance_valid(g):
			continue
		var apex: Vector2 = g.global_position
		var facing: Vector2 = g.get_facing()
		if facing.length() < 0.01:
			facing = Vector2.DOWN
		var dist: float = g.get_view_distance()
		var half: float = g.get_view_half_angle()
		var base_angle := facing.angle()
		var pts := PackedVector2Array([apex])
		for i in range(20):
			var a: float = base_angle - half + (2.0 * half) * float(i) / 20.0
			var endp := apex + Vector2.RIGHT.rotated(a) * dist
			var q := PhysicsRayQueryParameters2D.create(apex, endp, 1)
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			pts.append(hit["position"] if not hit.is_empty() else endp)
		var fill: Color
		if g.is_alert():
			fill = Color(1.0, 0.15, 0.15, 0.22)
		elif g.get_alert_ratio() > 0.05:
			fill = Color(1.0, 0.55, 0.0, 0.18)
		else:
			fill = Color(1.0, 1.0, 0.2, 0.12)
		draw_colored_polygon(pts, fill)


func _draw_bullets() -> void:
	if bullets == null:
		return
	for b in bullets.bullets:
		var p: Vector2 = b["pos"]
		var d: Vector2 = (b["dir"] as Vector2).normalized()
		var col := Color(1.0, 0.92, 0.4) if b["friendly"] else Color(1.0, 0.45, 0.2)
		draw_line(p - d * 16.0, p, Color(col.r, col.g, col.b, 0.45), 3.0)
		draw_circle(p, 3.0, col)
		draw_circle(p - d * 0.5, 1.4, Color(1, 1, 0.9))


func _draw_focus() -> void:
	if focus >= 0.999 and not focus_active:
		return
	var s: float = scale.x if scale.x > 0.001 else 1.0
	var vp := get_viewport_rect().size / s
	var origin := -position / s
	if focus_active:
		draw_rect(Rect2(origin, vp), Color(0.35, 0.55, 1.0, 0.08))
	var bw := 200.0 / s
	var bx := origin.x + vp.x * 0.5 - bw * 0.5
	var by := origin.y + vp.y - 56.0 / s
	draw_rect(Rect2(bx, by, bw, 9.0 / s), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bx, by, bw * focus, 9.0 / s), Color(0.6, 0.75, 1.0))
	_label_c("SANG-FROID (Maj)", Vector2(origin.x + vp.x * 0.5, by - 4.0 / s), maxi(6, int(12.0 / s)), Color(0.82, 0.9, 1.0))


# --- Primitives ---

func _spr(idx: int, pos: Vector2, w: float, h: float, mod := Color.WHITE, yoff := 0.0) -> void:
	draw_texture_rect_region(_sheet, Rect2(pos.x - w * 0.5, pos.y - h + yoff, w, h), _region(idx), mod)


func _shadow_spr(idx: int, pos: Vector2, w: float, h: float, yoff: float) -> void:
	draw_colored_polygon(_ellipse(pos + Vector2(0, 1), w * 0.42, w * 0.2), Color(0, 0, 0, 0.22))
	_spr(idx, pos, w, h, Color.WHITE, yoff)


func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(14):
		var a := TAU * float(i) / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _label_c(text: String, pos: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
