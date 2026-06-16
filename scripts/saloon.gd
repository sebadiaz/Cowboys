extends Node2D
## saloon.gd
## Intérieur du saloon (vue iso). On déambule, on parle au barman et aux clients
## (touche E), on admire le piano, puis on ressort par la porte (E près de la
## SORTIE ou Échap) pour revenir en ville. Tout est dessiné (aucun asset requis).

const SPEED := 220.0
const FLOOR := Rect2(0, 0, 1000, 680)
const DOOR := Vector2(500, 650)             # porte de sortie (bas)
const DOOR_RADIUS := 80.0
const PLAYER_RADIUS := 14.0
const TALK_RADIUS := 120.0   # un peu large pour parler au barman par-dessus le comptoir
const TOWN_EXIT := Vector2(760, 720)        # réapparition en ville (devant le saloon)

var _player_pos := Vector2(500, 600)
var _facing := Vector2.UP
var _walk := 0.0
var _hint_t := 0.0
var _near_label := ""
var _target_kind := ""        # "exit" | "npc"
var _target_npc = null
var _target_anchor := Vector2.ZERO
var _can_exit := false
var _interact_was := false
var _action_btn: Button
var _card_game = null          # overlay du jeu de cartes (null = fermé)

var _npcs: Array[Dictionary] = []
var _foots: Array[Rect2] = []
var _body: CharacterBody2D    # corps physique du joueur
var _world: Node2D            # sous-arbre physique (espace monde, sans caméra)
var _zoom := 2.2
var _cam := Vector2.ZERO
var _toast: Label
var _rng := RandomNumberGenerator.new()

# Mélodie du pianiste (indices dans la gamme ; -1 = silence).
const MELODY := [0, 2, 4, 2, 4, 5, 4, -1, 2, 4, 0, 2, 4, -1, 0, -1]
var _beat_t := 0.6
var _beat_i := 0


func _ready() -> void:
	Iso.top_down = false   # le saloon se dessine en iso
	Iso.yaw = 0.0          # le saloon se joue en vue iso fixe
	_rng.randomize()
	_build()
	_build_physics()
	_apply_zoom()
	_cam = _camera_target()
	position = _cam
	_build_ui()


## Vrai moteur de collision : corps joueur + StaticBody par meuble/mur (murs,
## comptoir, piano, tables). Sous-arbre top_level (espace monde, hors caméra).
func _build_physics() -> void:
	_world = Node2D.new()
	_world.top_level = true
	add_child(_world)
	_body = CharacterBody2D.new()
	_body.collision_layer = 2
	_body.collision_mask = 1
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PLAYER_RADIUS
	cs.shape = circle
	_body.add_child(cs)
	_body.position = _player_pos
	_world.add_child(_body)
	for r in _foots:
		var sb := StaticBody2D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		sb.position = r.position + r.size * 0.5
		var scs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size
		scs.shape = rect
		sb.add_child(scs)
		_world.add_child(sb)


func _physics_process(_delta: float) -> void:
	if _body == null or _card_game != null:
		return
	var dir := Iso.screen_to_world(InputManager.get_move_vector())
	if dir.length() > 1.0:
		dir = dir.normalized()
	if dir.length() > 0.05:
		_facing = dir.normalized()
		_walk += _delta * 10.0
	else:
		_walk = 0.0
	_body.velocity = dir * SPEED
	_body.move_and_slide()
	var p := _body.position
	p.x = clampf(p.x, 30, FLOOR.size.x - 30)
	p.y = clampf(p.y, 30, FLOOR.size.y - 10)
	_body.position = p
	_player_pos = p


func _build() -> void:
	# Murs (porte = trou en bas, x 420..580).
	for r in [Rect2(0, 0, 1000, 20), Rect2(0, 660, 420, 20), Rect2(580, 660, 420, 20),
			Rect2(0, 0, 20, 680), Rect2(980, 0, 20, 680)]:
		_foots.append(r)
	# Comptoir + piano (collisions).
	_foots.append(Rect2(140, 120, 720, 64))     # bar
	_foots.append(Rect2(800, 230, 120, 90))      # piano
	for t in [Vector2(250, 430), Vector2(500, 500), Vector2(700, 440)]:
		_foots.append(Rect2(t - Vector2(42, 30), Vector2(84, 60)))   # tables

	# Personnel & clients (chacun a ses répliques).
	_add_npc(Vector2(500, 95), Vector2(0, 1), Color(0.55, 0.4, 0.25), Color(0.9, 0.85, 0.7),
			"Sam le barman", ["Qu'est-ce que je te sers, l'ami ? On n'a plus que du whisky.",
			"La banque ? J'ai rien vu, rien entendu. Compris ?",
			"Pas d'embrouilles dans mon saloon."], 0.0)
	_add_npc(Vector2(250, 360), Vector2(0.3, 1), Color(0.3, 0.25, 0.4), Color(0.7, 0.6, 0.4),
			"Joueur de poker", ["Une partie ? Mise tout ton butin, ha !",
			"J'ai un carré d'as... ou pas."], 36.0)
	_add_npc(Vector2(835, 360), Vector2(-1, 0.2), Color(0.2, 0.3, 0.45), Color(0.85, 0.8, 0.8),
			"Pianiste", ["Une petite mélodie pour le hors-la-loi ?",
			"♪ Oh Susanna... ♪"], 0.0)
	_add_npc(Vector2(640, 560), Vector2(-0.4, -1), Color(0.5, 0.2, 0.2), Color(0.8, 0.7, 0.6),
			"Ivrogne", ["*hic* T'as pas une pièce, l'ami ?",
			"J'ai vu le shérif rentrer son or à la banque... *hic*"], 55.0)
	_add_npc(Vector2(700, 430), Vector2(-1, -0.3), Color(0.18, 0.16, 0.2), Color(0.25, 0.2, 0.15),
			"Pistolero", ["On règle ça dehors ? Le plus rapide rafle la mise.",
			"T'as la dégaine lente, gamin."], 24.0)


func _add_npc(pos: Vector2, facing: Vector2, coat: Color, hat: Color,
		npc_name: String, lines: Array, wander := 40.0) -> void:
	var pal := CharacterArt.hero_palette()
	pal["coat"] = coat
	pal["coat_dark"] = coat.darkened(0.2)
	pal["shirt"] = coat.lightened(0.2)
	pal["hat"] = hat
	pal["hat_band"] = hat.darkened(0.3)
	pal["bandana"] = coat.lightened(0.3)
	_npcs.append({"pos": pos, "facing": facing.normalized(), "pal": pal,
			"name": npc_name, "lines": lines, "li": 0, "wander": wander})


# --- Boucle ---

func _process(delta: float) -> void:
	# Déplacement du joueur (collision moteur) géré dans _physics_process.
	if _card_game != null:
		if _action_btn != null:
			_action_btn.visible = false
		return
	_update_interaction()
	for n in _npcs:
		NpcAI.update(n, delta, _blocked, _rng)
	_play_piano(delta)
	_cam = _cam.lerp(_camera_target(), clampf(delta * 8.0, 0.0, 1.0))
	position = _cam
	_hint_t += delta
	queue_redraw()


func _update_interaction() -> void:
	_can_exit = _player_pos.distance_to(DOOR) < DOOR_RADIUS
	_near_label = ""
	_target_kind = ""
	_target_npc = null
	if _can_exit:
		_target_kind = "exit"
		_near_label = "SORTIR du saloon"
		_target_anchor = DOOR
	else:
		var best := TALK_RADIUS
		for n in _npcs:
			var d := _player_pos.distance_to(n["pos"])
			if d < best:
				best = d
				_target_kind = "npc"
				_target_npc = n
				_near_label = ("JOUER aux cartes (21)" if str(n["name"]) == "Joueur de poker"
						else "PROVOQUER en duel" if str(n["name"]) == "Pistolero"
						else "Parler à %s" % n["name"])
				_target_anchor = n["pos"]
	var held := InputManager.is_interact_held()
	if held and not _interact_was:
		_do_action()
	_interact_was = held
	_update_action_button()


func _do_action() -> void:
	if _target_kind == "exit":
		_leave()
	elif _target_kind == "npc" and _target_npc != null:
		if str(_target_npc["name"]) == "Joueur de poker":
			_open_card_game()
		elif str(_target_npc["name"]) == "Pistolero":
			_open_duel()
		else:
			_talk(_target_npc)


## Ouvre la table de VINGT-ET-UN par-dessus le saloon (overlay screen-space).
func _open_card_game() -> void:
	if _card_game != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var cg = load("res://scripts/card_game.gd").new()
	layer.add_child(cg)
	cg.closed.connect(func():
		layer.queue_free()
		_card_game = null
		_interact_was = true)   # évite de rouvrir aussitôt avec la même pression
	_card_game = cg
	AudioManager.play("click")


## Ouvre le DUEL au pistolet par-dessus le saloon (même pause d'overlay).
func _open_duel() -> void:
	if _card_game != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var dg = load("res://scripts/duel_game.gd").new()
	layer.add_child(dg)
	dg.closed.connect(func():
		layer.queue_free()
		_card_game = null
		_interact_was = true)
	_card_game = dg
	AudioManager.play("click")


func _update_action_button() -> void:
	if _action_btn == null:
		return
	if _target_kind == "":
		_action_btn.visible = false
		return
	_action_btn.visible = true
	_action_btn.text = "%s\n%s" % ["🚪" if _target_kind == "exit" else "💬", _near_label]
	var local := Iso.project(_target_anchor) + Vector2(0, -40)
	_action_btn.position = position + local * scale - _action_btn.size * 0.5


## Le pianiste égrène la mélodie en boucle (ambiance saloon).
func _play_piano(delta: float) -> void:
	_beat_t -= delta
	if _beat_t > 0.0:
		return
	_beat_t = 0.34
	var n: int = MELODY[_beat_i]
	_beat_i = (_beat_i + 1) % MELODY.size()
	if n >= 0:
		AudioManager.play("piano%d" % n, -9.0, 0.0)


func _talk(npc) -> void:
	var lines: Array = npc["lines"]
	if lines.is_empty():
		return
	var i: int = npc["li"] % lines.size()
	npc["li"] = i + 1
	npc["state"] = "idle"
	npc["timer"] = 2.0
	npc["facing"] = (_player_pos - npc["pos"]).normalized()
	_facing = (npc["pos"] - _player_pos).normalized()
	_show_toast("%s : « %s »" % [npc["name"], lines[i]])


func _leave() -> void:
	AudioManager.play("click")
	GameManager.return_to_town(TOWN_EXIT)


## Toujours utilisé par l'IA des clients (déambulation sans traverser les meubles).
func _blocked(pos: Vector2) -> bool:
	for r in _foots:
		if r.grow(PLAYER_RADIUS).has_point(pos):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if _card_game != null:
		return
	if event.is_action_pressed("pause"):
		GameManager.return_to_town(TOWN_EXIT)


# --- Caméra qui suit ---

func _apply_zoom() -> void:
	var vp := get_viewport_rect().size
	_zoom = clampf(minf(vp.x, vp.y) / 360.0, 1.8, 3.0)
	scale = Vector2(_zoom, _zoom)


func _camera_target() -> Vector2:
	var vp := get_viewport_rect().size
	var b := _bounds()
	var focus := Iso.project(_player_pos) + Vector2(0, -16)
	var t := vp * 0.5 - focus * _zoom
	t.x = _clamp_axis(t.x, vp.x, b.position.x, b.end.x)
	t.y = _clamp_axis(t.y, vp.y, b.position.y, b.end.y)
	return t


func _clamp_axis(t: float, screen: float, bmin: float, bmax: float) -> float:
	var lo := screen - _zoom * bmax
	var hi := -_zoom * bmin
	if lo > hi:
		return screen * 0.5 - _zoom * (bmin + bmax) * 0.5
	return clampf(t, lo, hi)


func _bounds() -> Rect2:
	var c := [Iso.project(FLOOR.position), Iso.project(Vector2(FLOOR.size.x, 0)),
			Iso.project(FLOOR.size), Iso.project(Vector2(0, FLOOR.size.y))]
	var mn: Vector2 = c[0]
	var mx: Vector2 = c[0]
	for p in c:
		mn = mn.min(p)
		mx = mx.max(p)
	mn.y -= 220.0
	return Rect2(mn, mx - mn)


func _on_viewport_resized() -> void:
	_apply_zoom()
	_cam = _camera_target()
	position = _cam


# --- Rendu ---

func _draw() -> void:
	_draw_floor()
	# Tapis d'entrée + zone de sortie verte.
	draw_colored_polygon(_rect_diamond(Rect2(420, 600, 160, 80)), Color(0.2, 0.6, 0.25, 0.5))
	_text(Iso.project(DOOR) + Vector2(0, -10), "SORTIE", 14, Color(0.9, 1, 0.9))

	# Murs bas (boîtes) pour donner du volume à la pièce.
	_box(Rect2(0, 0, 1000, 20), 70.0, Color(0.45, 0.30, 0.18), Color(0.32, 0.2, 0.12))
	_box(Rect2(0, 0, 20, 680), 70.0, Color(0.42, 0.28, 0.16), Color(0.3, 0.19, 0.11))
	_box(Rect2(980, 0, 20, 680), 70.0, Color(0.42, 0.28, 0.16), Color(0.3, 0.19, 0.11))

	# Étagère à bouteilles derrière le bar.
	for i in range(10):
		var x := 180.0 + i * 64.0
		draw_circle(Iso.project(Vector2(x, 70)) + Vector2(0, -54), 4.0,
				Color(0.3, 0.6, 0.3) if i % 2 == 0 else Color(0.6, 0.4, 0.2))

	# Profondeur : trie bar, piano, tables, PNJ, joueur.
	var items: Array[Dictionary] = []
	items.append({"d": Iso.depth(Vector2(500, 184)), "k": "bar"})
	items.append({"d": Iso.depth(Vector2(860, 320)), "k": "piano"})
	for t in [Vector2(250, 430), Vector2(500, 500), Vector2(700, 440)]:
		items.append({"d": Iso.depth(t), "k": "table", "p": t})
	for n in _npcs:
		items.append({"d": Iso.depth(n["pos"]), "k": "npc", "o": n})
	items.append({"d": Iso.depth(_player_pos), "k": "me"})
	items.sort_custom(func(a, b): return a["d"] < b["d"])
	for it in items:
		match it["k"]:
			"bar": _box(Rect2(140, 120, 720, 64), 40.0, Color(0.55, 0.36, 0.2), Color(0.38, 0.24, 0.13))
			"piano": _box(Rect2(800, 230, 120, 90), 60.0, Color(0.12, 0.1, 0.1), Color(0.07, 0.06, 0.06))
			"table": _draw_table(it["p"])
			"npc":
				var n: Dictionary = it["o"]
				CharacterArt.draw_person(self, Iso.project(n["pos"]), _sf(n["pos"], n["facing"]),
						n["pal"], false, false, float(n.get("walk", 0.0)), 0.0, 0.0)
			"me":
				CharacterArt.draw_person(self, Iso.project(_player_pos), _sf(_player_pos, _facing),
						CharacterArt.hero_palette(), false, false, _walk, 0.0, 0.0)

	# Bulles d'ambiance + marqueurs de dialogue.
	for n in _npcs:
		var head := Iso.project(n["pos"]) + Vector2(0, -56)
		var bub := NpcAI.bubble(n)
		if bub != "":
			_text(head, bub, 15, Color(1, 1, 0.9))
		elif _player_pos.distance_to(n["pos"]) < TALK_RADIUS:
			_text(head, "💬", 16, Color(1, 1, 0.7))


func _draw_floor() -> void:
	var cell := 80.0
	var y := 0.0
	var row := 0
	while y < FLOOR.size.y:
		var x := 0.0
		var col := 0
		while x < FLOOR.size.x:
			var w: float = min(cell, FLOOR.size.x - x)
			var h: float = min(cell, FLOOR.size.y - y)
			var c := Color(0.46, 0.31, 0.18) if (row + col) % 2 == 0 else Color(0.40, 0.27, 0.15)
			draw_colored_polygon(_rect_diamond(Rect2(x, y, w, h)), c)
			x += cell
			col += 1
		y += cell
		row += 1


func _draw_table(p: Vector2) -> void:
	draw_colored_polygon(_diamond_shadow(Iso.project(p), 26.0), Color(0, 0, 0, 0.2))
	_box(Rect2(p.x - 26, p.y - 18, 52, 36), 26.0, Color(0.5, 0.33, 0.18), Color(0.34, 0.22, 0.12))
	# Verre sur la table.
	draw_circle(Iso.project(p) + Vector2(6, -30), 2.4, Color(0.8, 0.7, 0.3))


## Petite boîte iso (meuble) : faces avant + dessus.
func _box(r: Rect2, h: float, top: Color, side: Color) -> void:
	var b0 := Iso.project(r.position)
	var b1 := Iso.project(Vector2(r.end.x, r.position.y))
	var b2 := Iso.project(r.end)
	var b3 := Iso.project(Vector2(r.position.x, r.end.y))
	var up := Vector2(0, -h)
	draw_colored_polygon(PackedVector2Array([b3, b2, b2 + up, b3 + up]), side.darkened(0.1))
	draw_colored_polygon(PackedVector2Array([b1, b2, b2 + up, b1 + up]), side)
	draw_colored_polygon(PackedVector2Array([b0 + up, b1 + up, b2 + up, b3 + up]), top)


# --- Primitives ---

func _rect_diamond(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		Iso.project(r.position), Iso.project(Vector2(r.end.x, r.position.y)),
		Iso.project(r.end), Iso.project(Vector2(r.position.x, r.end.y))])


func _diamond_shadow(center: Vector2, rx: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-rx, 0), center + Vector2(0, -rx * 0.5),
		center + Vector2(rx, 0), center + Vector2(0, rx * 0.5)])


func _sf(world_pos: Vector2, facing: Vector2) -> Vector2:
	var f := Iso.project(world_pos + facing) - Iso.project(world_pos)
	return f.normalized() if f.length() > 0.001 else Vector2.DOWN


func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# --- UI ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	get_viewport().size_changed.connect(_on_viewport_resized)

	var title := Label.new()
	title.text = "SALOON LE CACTUS — clique le logo (ou E) pour parler / sortir"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 4)
	title.position = Vector2(16, 12)
	layer.add_child(title)

	var back := Button.new()
	back.text = "← Ville"
	back.add_theme_font_size_override("font_size", 20)
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.position = Vector2(-150, 12)
	back.custom_minimum_size = Vector2(130, 44)
	back.pressed.connect(func() -> void: GameManager.return_to_town(TOWN_EXIT))
	layer.add_child(back)

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Color(1, 1, 0.85))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_toast.add_theme_constant_override("outline_size", 5)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = 40
	_toast.offset_right = -40
	_toast.offset_top = -150
	_toast.offset_bottom = -64
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_toast)

	var mc := Control.new()
	mc.set_script(load("res://scripts/mobile_controls.gd"))
	mc.set("combat_buttons", false)
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(mc)

	# Pastille d'action contextuelle (devant la SORTIE ou un client), cliquable.
	_action_btn = _make_action_button()
	layer.add_child(_action_btn)


func _make_action_button() -> Button:
	var b := Button.new()
	b.size = Vector2(190, 66)
	b.custom_minimum_size = b.size
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.visible = false
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(1, 1, 0.88))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	b.add_theme_constant_override("outline_size", 4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.30, 0.18, 0.08, 0.92)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.95, 0.8, 0.3)
	b.add_theme_stylebox_override("normal", sb)
	var hb := sb.duplicate()
	hb.bg_color = Color(0.42, 0.26, 0.12, 0.96)
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("pressed", hb)
	b.pressed.connect(func(): _do_action())
	return b


func _show_toast(text: String) -> void:
	if _toast == null:
		return
	AudioManager.play("click", -6.0)
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)
