extends Node2D
## town.gd
## Grand village western EXPLORABLE (vue iso). Caméra qui SUIT le cowboy : on
## déambule dans les rues, on croise des habitants, on inspecte les commerces
## (touche E = petit texte d'ambiance) et on entre dans la BANQUE (E) pour lancer
## le braquage. Collisions sur les bâtiments + le puits.

const SHEET := preload("res://assets/source_sheets/western_exterior_sheet.png")
const TEX := 1254.0

const R_SAND := Rect2(58, 58, 236, 214)
const R_BANK := Rect2(63, 1003, 251, 199)
const R_SALOON := Rect2(366, 1000, 240, 205)
const R_HOUSE := Rect2(648, 1010, 251, 192)
const R_SHED := Rect2(930, 1010, 240, 192)
const R_WAGON := Rect2(620, 600, 300, 200)
const R_CACTUS := Rect2(40, 555, 120, 200)
const R_BARREL := Rect2(40, 800, 120, 130)
const R_SIGN := Rect2(360, 800, 120, 160)

const SPEED := 250.0
const FLOOR := Rect2(0, 0, 2200, 1760)
const BANK_DOOR := Vector2(1100, 430)
const DOOR_RADIUS := 95.0
const PLAYER_RADIUS := 15.0
const TALK_RADIUS := 95.0
const WELL := Vector2(1100, 980)
const TOWN_RETURN_MAGASIN := Vector2(760, 1360)   # réapparition devant le Magasin

var _player_pos := Vector2(1100, 1620)
var _facing := Vector2.UP
var _walk := 0.0
var _entered := false
var _hint_t := 0.0
var _can_enter := false
var _near_label := ""        # libellé du prompt d'action courant
var _target_kind := ""       # "bank" | "saloon" | "npc" | "flavor"
var _target_npc = null       # PNJ ciblé (Dictionary) si _target_kind == "npc"
var _target_flavor := ""
var _target_anchor := Vector2.ZERO   # point MONDE où afficher le logo d'action
var _interact_was := false
var _action_btn: Button
var _horses: Array[Vector2] = []     # chevaux attachés (décor solide + caresse)

const HORSE_LINES := ["Un fier mustang, prêt à filer après le coup.",
	"*hennissement* Doux, mon beau...", "Ce cheval ferait une belle monture de fuite."]

var _buildings: Array[Dictionary] = []   # {region,pos,h,label,tint,flavor}
var _props: Array[Dictionary] = []        # {region,pos,h}
var _biome_decor: Array[Dictionary] = []  # {type,pos} décor propre au biome
var _npcs: Array[Dictionary] = []         # {pos,facing,pal,phase}
var _foots: Array[Rect2] = []             # empreintes de collision (décor solide)
var _body: CharacterBody2D                # corps physique du joueur (vrai moteur)
var _world: Node2D                        # sous-arbre physique (espace monde, sans caméra)

var _zoom := 2.0
var _cam := Vector2.ZERO
var _yaw_target := 0.0      # angle de vue visé (la vue s'y rend en douceur)
var _toast: Label
var _rng := RandomNumberGenerator.new()

# Diligence qui traverse la grande rue (ambiance).
const COACH_A := Vector2(1010, 120)
const COACH_B := Vector2(1010, 1720)
const COACH_SPEED := 135.0
var _coach_pos := COACH_A
var _coach_wait := 2.5
var _dust_t := 0.0


func _ready() -> void:
	_rng.randomize()
	Iso.yaw = 0.0
	_yaw_target = 0.0
	# Réapparition à la sortie du saloon (sinon, entrée du village).
	if GameManager.town_return_pos != Vector2.ZERO:
		_player_pos = GameManager.town_return_pos
		_facing = Vector2.DOWN
		GameManager.town_return_pos = Vector2.ZERO
	_build_town()
	_make_biome_decor()
	_build_physics()
	_apply_zoom()
	_cam = _camera_target()
	position = _cam
	_build_ui()
	_setup_atmosphere()
	AudioManager.play_music("theme")


## Teinte d'ambiance propre à chaque ville (désert, canyon rouge, neige, nuit…).
func _town_tint() -> Color:
	match str(GameManager.current_town_def().get("theme", "desert")):
		"canyon": return Color(1.12, 0.74, 0.55)
		"plains": return Color(0.92, 1.02, 0.80)
		"snow": return Color(0.80, 0.90, 1.14)
		"night": return Color(0.40, 0.46, 0.82)
		"sunset": return Color(1.14, 0.68, 0.46)
		_: return Color(1.04, 0.96, 0.80)


## Ambiance "golden hour" : teinte chaude globale + voile vignette doux sur les
## bords (rapproche le rendu de l'illustration western de référence).
func _setup_atmosphere() -> void:
	var warm := CanvasModulate.new()
	warm.color = _town_tint()
	add_child(warm)
	var layer := CanvasLayer.new()
	layer.layer = 1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\n" + \
		"void fragment() {\n" + \
		"  vec2 d = UV - vec2(0.5);\n" + \
		"  float r = length(d * vec2(1.05, 1.35));\n" + \
		"  float vig = smoothstep(0.42, 0.95, r);\n" + \
		"  vec3 tint = mix(vec3(0.55, 0.30, 0.12), vec3(0.04, 0.02, 0.05), 0.35);\n" + \
		"  COLOR = vec4(tint, vig * 0.5);\n" + \
		"}\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)


## Crée le VRAI moteur de collision : un corps pour le joueur + un StaticBody2D
## solide par empreinte de décor (bâtiments, props, puits, chevaux). Le décor a
## donc un volume et le joueur ne le traverse plus (glisse le long).
func _build_physics() -> void:
	# Sous-arbre en espace MONDE (top_level = ignore la transform caméra du parent).
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


func _physics_process(delta: float) -> void:
	if _entered or _body == null:
		return
	var dir := Iso.screen_to_world(InputManager.get_move_vector())
	if dir.length() > 1.0:
		dir = dir.normalized()
	if dir.length() > 0.05:
		_facing = dir.normalized()
		_walk += delta * 10.0
	else:
		_walk = 0.0
	_body.velocity = dir * SPEED
	_body.move_and_slide()
	# Bornage à la carte (au cas où) + synchro de la position de rendu.
	var p := _body.position
	p.x = clampf(p.x, FLOOR.position.x + 40, FLOOR.end.x - 40)
	p.y = clampf(p.y, FLOOR.position.y + 40, FLOOR.end.y - 40)
	_body.position = p
	_player_pos = p


# --- Construction du village ---

func _build_town() -> void:
	# Bâtiment cible, au fond de la grand-rue.
	_add_building(R_BANK, Vector2(1100, 230), 250.0, "★ BANQUE ★", Color(1, 1, 1),
			"", Vector2(256, 168))
	# Côté ouest de la rue (x ~ 760). Le SALOON est ENTRABLE.
	_add_building(R_SALOON, Vector2(760, 560), 210.0, "SALOON", Color(1.0, 0.92, 0.9),
			"Saloon Le Cactus — pousse les portes battantes.", Vector2(180, 120), "saloon")
	_add_building(R_HOUSE, Vector2(760, 900), 195.0, "HÔTEL", Color(0.92, 0.96, 1.0),
			"Hôtel de la Frontière — chambres à l'étage, 2 $ la nuit.", Vector2(180, 120))
	_add_building(R_SHED, Vector2(760, 1240), 185.0, "MAGASIN", Color(1.0, 0.96, 0.85),
			"Magasin général — améliore ton équipement.", Vector2(170, 115), "shop")
	_add_building(R_HOUSE, Vector2(760, 1560), 190.0, "ÉGLISE", Color(0.95, 0.95, 1.0),
			"Petite église en bois — une prière avant le casse ?", Vector2(170, 115))
	# Côté est de la rue (x ~ 1440).
	_add_building(R_HOUSE, Vector2(1440, 560), 195.0, "SHÉRIF", Color(0.85, 0.9, 1.0),
			"Bureau du shérif — mieux vaut filer avant qu'il ne rentre.", Vector2(180, 120))
	_add_building(R_SHED, Vector2(1440, 900), 185.0, "ÉCURIE", Color(0.95, 0.88, 0.78),
			"Écurie — ton cheval est sellé, prêt pour la fuite.", Vector2(170, 115))
	_add_building(R_SALOON, Vector2(1440, 1240), 205.0, "POSTE", Color(0.9, 1.0, 0.9),
			"Poste & télégraphe — « STOP braquage en cours STOP ».", Vector2(180, 120))
	_add_building(R_SHED, Vector2(1440, 1560), 185.0, "FORGE", Color(1.0, 0.9, 0.8),
			"Forge du maréchal-ferrant — l'odeur du fer chaud.", Vector2(170, 115))
	# Ruelle est (au-delà de la place).
	_add_building(R_HOUSE, Vector2(1820, 1020), 190.0, "DOCTEUR", Color(0.9, 1.0, 0.95),
			"Cabinet du Doc — whisky en guise d'anesthésie.", Vector2(170, 115))
	_add_building(R_SHED, Vector2(360, 1020), 185.0, "MAISON", Color(0.95, 0.92, 0.85),
			"Maison de ville — volets clos.", Vector2(170, 115))

	# Mobilier de rue (décor, sans collision).
	_add_prop(R_WAGON, Vector2(940, 760), 150.0)
	_add_prop(R_WAGON, Vector2(1280, 1360), 150.0)
	_add_prop(R_SIGN, Vector2(1100, 640), 100.0)
	_add_prop(R_BARREL, Vector2(960, 480), 78.0)
	_add_prop(R_BARREL, Vector2(1240, 520), 78.0)
	_add_prop(R_BARREL, Vector2(960, 1180), 78.0)
	_add_prop(R_BARREL, Vector2(1250, 1120), 78.0)
	for c in [Vector2(180, 560), Vector2(2020, 700), Vector2(160, 1480),
			Vector2(2040, 1500), Vector2(120, 900), Vector2(2080, 1100)]:
		_add_prop(R_CACTUS, c, 130.0)

	# Habitants : cowboys aux palettes variées, chacun a quelques répliques.
	_add_npc(Vector2(980, 1080), Vector2(1, 0.2), Color(0.30, 0.45, 0.55), Color(0.85, 0.8, 0.7),
			"Vieux Hank", ["La banque ? Personne n'a jamais réussi à la braquer...",
			"Le shérif a la gâchette facile, méfie-toi.",
			"De mon temps, l'or coulait à flots dans cette ville."])
	_add_npc(Vector2(1230, 880), Vector2(-1, 0.2), Color(0.45, 0.30, 0.45), Color(0.9, 0.85, 0.5),
			"Rosita", ["Tu as l'air d'un homme à histoires, étranger.",
			"Le coffre de la banque ? On dit qu'il faut un moment pour l'ouvrir."])
	_add_npc(Vector2(1100, 1180), Vector2(0, 1), Color(0.25, 0.35, 0.25), Color(0.8, 0.7, 0.55),
			"Petit Joe", ["Wow, t'as vu son flingue ?!", "Un jour je serai un hors-la-loi, moi aussi !"])
	_add_npc(Vector2(1180, 700), Vector2(-0.4, 1), Color(0.5, 0.4, 0.2), Color(0.95, 0.7, 0.2),
			"Marshal à la retraite", ["Range ce six-coups avant de t'attirer des ennuis.",
			"J'ai accroché mon étoile. La ville se débrouillera."])
	_add_npc(Vector2(1000, 1380), Vector2(1, -0.3), Color(0.5, 0.2, 0.2), Color(0.8, 0.75, 0.7),
			"Veuve Carson", ["Les temps sont durs depuis la fermeture de la mine.",
			"Garde tes distances, jeune homme."])
	_add_npc(Vector2(1300, 1480), Vector2(-1, -0.2), Color(0.2, 0.3, 0.5), Color(0.9, 0.9, 0.8),
			"Doc Whitman", ["Si tu te prends une balle, tu sais où me trouver.",
			"Le whisky soigne tout, ou presque."])
	_add_npc(Vector2(1700, 1080), Vector2(-1, 0.1), Color(0.4, 0.45, 0.3), Color(0.85, 0.6, 0.4),
			"Palefrenier", ["Ton cheval est sellé à l'écurie, prêt pour la fuite.",
			"File vite après le coup, ils lanceront une battue."])
	_add_npc(Vector2(520, 1080), Vector2(1, 0.1), Color(0.35, 0.3, 0.45), Color(0.9, 0.8, 0.6),
			"Prêcheur", ["Repens-toi, pécheur, avant qu'il ne soit trop tard !",
			"Que le Seigneur ait pitié de ton âme... et de ton butin."])

	# Puits central (collision).
	_foots.append(Rect2(WELL - Vector2(40, 36), Vector2(80, 72)))

	# Chevaux attachés devant l'ÉCURIE (décor solide + on peut les caresser).
	for hp in [Vector2(1360, 1030), Vector2(1440, 1040), Vector2(1520, 1030)]:
		_horses.append(hp)
		_foots.append(Rect2(hp - Vector2(17, 12), Vector2(34, 24)))


func _add_building(region: Rect2, pos: Vector2, h: float, label: String, tint: Color,
		flavor: String, foot: Vector2, enter := "") -> void:
	var foot_rect := Rect2(pos - Vector2(foot.x * 0.5, foot.y * 0.6), foot)
	_buildings.append({"region": region, "pos": pos, "h": h, "label": label,
			"tint": tint, "flavor": flavor, "enter": enter, "foot": foot_rect})
	_foots.append(foot_rect)


func _add_prop(region: Rect2, pos: Vector2, h: float) -> void:
	_props.append({"region": region, "pos": pos, "h": h})
	# Décor SOLIDE : empreinte de collision selon le type (on ne traverse plus).
	var sz := Vector2.ZERO
	match region:
		R_WAGON: sz = Vector2(86, 48)
		R_CACTUS: sz = Vector2(26, 26)
		R_BARREL: sz = Vector2(28, 28)
		R_SIGN: sz = Vector2(20, 20)
	if sz != Vector2.ZERO:
		_foots.append(Rect2(pos - sz * 0.5, sz))


func _add_npc(pos: Vector2, facing: Vector2, coat: Color, hat: Color,
		npc_name := "", lines: Array = []) -> void:
	var pal := CharacterArt.hero_palette()
	pal["coat"] = coat
	pal["coat_dark"] = coat.darkened(0.2)
	pal["shirt"] = coat.lightened(0.2)
	pal["hat"] = hat
	pal["hat_band"] = hat.darkened(0.3)
	pal["bandana"] = coat.lightened(0.3)
	_npcs.append({"pos": pos, "facing": facing.normalized(), "pal": pal, "phase": randf() * TAU,
			"name": npc_name, "lines": lines, "li": 0})


# --- Boucle ---

func _process(delta: float) -> void:
	# Le déplacement du joueur (collision moteur) est dans _physics_process.
	if not _entered:
		_update_interaction()
	for n in _npcs:
		NpcAI.update(n, delta, _blocked, _rng)
	_update_coach(delta)
	# Rotation douce de la vue vers l'angle visé (pivote tout le décor).
	if absf(angle_difference(Iso.yaw, _yaw_target)) > 0.0005:
		Iso.yaw = lerp_angle(Iso.yaw, _yaw_target, clampf(delta * 9.0, 0.0, 1.0))
	_cam = _cam.lerp(_camera_target(), clampf(delta * 8.0, 0.0, 1.0))
	position = _cam
	_hint_t += delta
	queue_redraw()


## Fait pivoter la vue par pas de 45° (la simulation reste inchangée).
func _rotate_view(steps: int) -> void:
	_yaw_target += float(steps) * PI / 4.0


## Choisit l'interaction la plus proche (banque, saloon, PNJ, commerce) et gère E.
func _update_interaction() -> void:
	_can_enter = _player_pos.distance_to(BANK_DOOR) < DOOR_RADIUS
	_near_label = ""
	_target_kind = ""
	_target_npc = null
	_target_flavor = ""
	if _can_enter:
		_target_kind = "bank"
		_near_label = "ENTRER dans la BANQUE"
		_target_anchor = BANK_DOOR
	else:
		var best := TALK_RADIUS
		# Habitants à qui parler (priorité au plus proche).
		for n in _npcs:
			if (n["lines"] as Array).is_empty():
				continue
			var d := _player_pos.distance_to(n["pos"])
			if d < best:
				best = d
				_target_kind = "npc"
				_target_npc = n
				_near_label = "Parler à %s" % n["name"]
				_target_anchor = n["pos"]
		# Commerces : entrer (saloon) ou observer (texte d'ambiance).
		for b in _buildings:
			if b["flavor"] == "" and b["enter"] == "":
				continue
			var d := _player_pos.distance_to(b["pos"] + Vector2(0, 60))
			if d < best:
				best = d
				_target_anchor = b["pos"] + Vector2(0, 60)
				if b["enter"] != "":
					_target_kind = b["enter"]   # "saloon" | "shop"
					_near_label = "Entrer au %s" % b["label"]
				else:
					_target_kind = "flavor"
					_target_flavor = b["flavor"]
					_near_label = b["label"]
		# Chevaux à caresser.
		for hp in _horses:
			var d := _player_pos.distance_to(hp)
			if d < best:
				best = d
				_target_kind = "horse"
				_near_label = "Caresser le cheval"
				_target_anchor = hp
	# Touche E (front montant) = même action que le logo cliquable.
	var held := InputManager.is_interact_held()
	if held and not _interact_was:
		_do_action()
	_interact_was = held
	_update_action_button()


## Exécute l'action de la cible courante (E clavier OU clic sur le logo).
func _do_action() -> void:
	match _target_kind:
		"bank": _enter_bank()
		"saloon": GameManager.goto_saloon()
		"shop": GameManager.goto_shop_from_town(TOWN_RETURN_MAGASIN)
		"npc": _talk(_target_npc)
		"horse": _show_toast(HORSE_LINES[_rng.randi() % HORSE_LINES.size()])
		"flavor": _show_toast(_target_flavor)


## Icône d'action (emoji) selon le type de cible.
func _action_icon() -> String:
	match _target_kind:
		"bank", "saloon": return "🚪"
		"shop": return "🛒"
		"npc": return "💬"
		"horse": return "🐴"
		"flavor": return "👁"
	return ""


## Place/affiche la pastille cliquable devant la porte/cible quand on est proche.
func _update_action_button() -> void:
	if _action_btn == null:
		return
	if _target_kind == "":
		_action_btn.visible = false
		return
	_action_btn.visible = true
	_action_btn.text = "%s\n%s" % [_action_icon(), _near_label]
	# Projection MONDE -> écran (le noeud porte le zoom/position de caméra).
	var local := Iso.project(_target_anchor) + Vector2(0, -40)
	var screen := position + local * scale
	_action_btn.position = screen - _action_btn.size * 0.5


## Affiche la réplique courante d'un PNJ et passe à la suivante.
func _talk(npc) -> void:
	var lines: Array = npc["lines"]
	if lines.is_empty():
		return
	var i: int = npc["li"] % lines.size()
	npc["li"] = i + 1
	# Le PNJ s'arrête et se tourne vers le joueur (conversation).
	npc["state"] = "idle"
	npc["timer"] = 2.0
	npc["facing"] = (_player_pos - npc["pos"]).normalized()
	_facing = (npc["pos"] - _player_pos).normalized()
	_show_toast("%s : « %s »" % [npc["name"], lines[i]])


## Diligence : descend la rue, attend, puis recommence. Laisse un peu de poussière.
func _update_coach(delta: float) -> void:
	if _coach_wait > 0.0:
		_coach_wait -= delta
		if _coach_wait <= 0.0:
			_coach_pos = COACH_A
		return
	_coach_pos.y += COACH_SPEED * delta
	_dust_t -= delta
	if _coach_pos.y >= COACH_B.y:
		_coach_wait = _rng.randf_range(5.0, 9.0)


func _coach_active() -> bool:
	return _coach_wait <= 0.0


## Toujours utilisé par l'IA des PNJ (déambulation sans traverser le décor).
func _blocked(pos: Vector2) -> bool:
	for r in _foots:
		if r.grow(PLAYER_RADIUS).has_point(pos):
			return true
	return false


func _enter_bank() -> void:
	_entered = true
	AudioManager.play("click")
	GameManager.start_mission()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameManager.goto_main_menu()
	elif event is InputEventKey and event.pressed and not event.echo:
		# Pivoter la vue par pas de 45° (touches sans conflit avec le déplacement).
		match event.keycode:
			KEY_BRACKETLEFT, KEY_COMMA: _rotate_view(-1)
			KEY_BRACKETRIGHT, KEY_PERIOD: _rotate_view(1)


# --- Caméra qui suit le cowboy (bornée à la carte) ---

func _apply_zoom() -> void:
	var vp := get_viewport_rect().size
	_zoom = clampf(minf(vp.x, vp.y) / 380.0, 1.7, 2.8)
	scale = Vector2(_zoom, _zoom)


func _camera_target() -> Vector2:
	var vp := get_viewport_rect().size
	var b := _map_bounds()
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


func _map_bounds() -> Rect2:
	var c := [Iso.project(FLOOR.position), Iso.project(Vector2(FLOOR.end.x, FLOOR.position.y)),
			Iso.project(FLOOR.end), Iso.project(Vector2(FLOOR.position.x, FLOOR.end.y))]
	var mn: Vector2 = c[0]
	var mx: Vector2 = c[0]
	for p in c:
		mn = mn.min(p)
		mx = mx.max(p)
	mn.y -= 280.0
	return Rect2(mn, mx - mn)


func _on_viewport_resized() -> void:
	_apply_zoom()
	_cam = _camera_target()
	position = _cam


# --- Rendu iso (coords locales : la caméra = position/scale du noeud) ---

func _draw() -> void:
	_draw_ground()
	_draw_well()
	_draw_hitch()
	# Repère banque : halo doré + flèche flottante.
	var d := Iso.project(BANK_DOOR)
	for i in range(4):
		draw_circle(d + Vector2(0, -6), 70.0 - i * 14.0, Color(1.0, 0.85, 0.35, 0.10))
	var bob := sin(_hint_t * 3.0) * 4.0
	var arrow := d + Vector2(0, -60 + bob)
	draw_colored_polygon(PackedVector2Array([
		arrow + Vector2(-10, -10), arrow + Vector2(10, -10), arrow + Vector2(0, 2)]),
		Color(1.0, 0.85, 0.25))
	_text(arrow + Vector2(0, -16), "BANQUE", 15, Color(1.0, 0.92, 0.6))

	var items: Array[Dictionary] = []
	for b in _buildings:
		items.append({"d": Iso.depth(b["pos"]) - 40.0, "k": "b", "o": b})
	for p in _props:
		items.append({"d": Iso.depth(p["pos"]), "k": "p", "o": p})
	for bd in _biome_decor:
		items.append({"d": Iso.depth(bd["pos"]), "k": "bio", "o": bd})
	for n in _npcs:
		items.append({"d": Iso.depth(n["pos"]), "k": "n", "o": n})
	for hp in _horses:
		items.append({"d": Iso.depth(hp), "k": "horse", "o": hp})
	if _coach_active():
		items.append({"d": Iso.depth(_coach_pos), "k": "coach", "o": null})
	items.append({"d": Iso.depth(_player_pos), "k": "me", "o": null})
	items.sort_custom(func(a, b): return a["d"] < b["d"])
	for it in items:
		match it["k"]:
			"b": _draw_building(it["o"])
			"p":
				var reg: Rect2 = it["o"]["region"]
				if reg == R_WAGON:
					_draw_wagon(it["o"]["pos"])   # chariots garés en volume
				elif reg == R_BARREL:
					_draw_barrel(it["o"]["pos"])
				elif reg == R_CACTUS:
					_draw_cactus(it["o"]["pos"])
				else:
					_billboard(reg, it["o"]["pos"], it["o"]["h"], Color.WHITE)
			"bio": _draw_bio(it["o"]["type"], it["o"]["pos"])
			"coach": _draw_coach()
			"horse": _horse(it["o"])
			"n":
				var n: Dictionary = it["o"]
				var f := _screen_facing(n["pos"], n["facing"])
				CharacterArt.draw_person(self, Iso.project(n["pos"]), f, n["pal"],
						false, false, float(n.get("walk", 0.0)), 0.0, 0.0)
			"me": _draw_me()

	# Bulles d'ambiance + marqueur "💬" pour les PNJ.
	for n in _npcs:
		var head := Iso.project(n["pos"]) + Vector2(0, -58)
		var bub := NpcAI.bubble(n)
		if bub != "":
			_text(head, bub, 15, Color(1, 1, 0.9))
		elif not (n["lines"] as Array).is_empty() and _player_pos.distance_to(n["pos"]) < TALK_RADIUS:
			_text(head, "💬", 16, Color(1, 1, 0.7))


func _draw_ground() -> void:
	var cell := 160.0
	var y := FLOOR.position.y
	while y < FLOOR.end.y - 1.0:
		var x := FLOOR.position.x
		while x < FLOOR.end.x - 1.0:
			_sand_tile(x, y, minf(cell, FLOOR.end.x - x), minf(cell, FLOOR.end.y - y))
			x += cell
		y += cell
	# Grand-rue (terre plus sombre) + place centrale.
	draw_colored_polygon(_rect_diamond(Rect2(900, 120, 400, 1560)), Color(0.55, 0.42, 0.28, 0.45))
	draw_colored_polygon(_rect_diamond(Rect2(880, 860, 440, 320)), Color(0.5, 0.38, 0.25, 0.4))
	for b in _buildings:
		var pos: Vector2 = b["pos"]
		var plank := _rect_diamond(Rect2(pos.x - 95, pos.y + 30, 190, 70))
		draw_colored_polygon(plank, Color(0.52, 0.36, 0.20, 0.9))
		draw_polyline(_closed(plank), Color(0.35, 0.24, 0.13), 2.0)
	_draw_biome_ground()


## Décor propre au biome (déterministe par ville) : disposé sur les bords pour ne
## pas gêner la circulation. Rend chaque ville visuellement unique.
func _make_biome_decor() -> void:
	_biome_decor.clear()
	var theme := str(GameManager.current_town_def().get("theme", "desert"))
	var kinds: Array
	match theme:
		"canyon": kinds = ["rock", "rock", "cactus", "skull"]
		"plains": kinds = ["bush", "pine", "bush", "bush"]
		"snow": kinds = ["pine_snow", "rock", "pine_snow", "pine_snow"]
		"night": kinds = ["lamp", "pine", "rock", "lamp"]
		"sunset": kinds = ["cactus", "rock", "skull", "cactus"]
		_: kinds = ["cactus", "skull", "rock", "cactus"]
	var rng := RandomNumberGenerator.new()
	rng.seed = GameManager.current_town * 131 + 17
	# Bandes périphériques (évitent le centre bâti / la grand-rue).
	var spots := []
	for yy in range(120, 1700, 150):
		spots.append(Vector2(rng.randf_range(70, 300), yy))
		spots.append(Vector2(rng.randf_range(1900, 2130), yy))
	for xx in range(360, 1860, 220):
		spots.append(Vector2(xx, rng.randf_range(70, 170)))
		spots.append(Vector2(xx, rng.randf_range(1640, 1700)))
	spots.shuffle()
	var count := mini(spots.size(), 22)
	for i in range(count):
		_biome_decor.append({"type": kinds[rng.randi() % kinds.size()], "pos": spots[i]})


func _draw_biome_ground() -> void:
	var theme := str(GameManager.current_town_def().get("theme", "desert"))
	var col: Color
	match theme:
		"snow": col = Color(0.92, 0.95, 1.0, 0.55)
		"plains": col = Color(0.45, 0.62, 0.32, 0.35)
		"canyon": col = Color(0.62, 0.32, 0.20, 0.30)
		"night": col = Color(0.20, 0.24, 0.40, 0.30)
		"sunset": col = Color(0.80, 0.45, 0.30, 0.22)
		_: col = Color(0.78, 0.66, 0.42, 0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameManager.current_town * 911 + 3
	for i in range(26):
		var c := Vector2(rng.randf_range(60, 2140), rng.randf_range(80, 1700))
		# On évite la grande rue centrale.
		if c.x > 880 and c.x < 1320:
			continue
		var w := rng.randf_range(60, 130)
		draw_colored_polygon(_rect_diamond(Rect2(c.x - w * 0.5, c.y - w * 0.4, w, w * 0.8)), col)


## Aiguillage du décor de biome.
func _draw_bio(t: String, pos: Vector2) -> void:
	match t:
		"cactus": _draw_cactus(pos)
		"rock": _draw_rock(pos)
		"bush": _draw_bush(pos)
		"skull": _draw_skull(pos)
		"pine": _draw_pine(pos, false)
		"pine_snow": _draw_pine(pos, true)
		"lamp": _draw_lamp_post(pos)
		_: _draw_rock(pos)


func _draw_pine(pos: Vector2, snowy: bool) -> void:
	var base := Iso.project(pos)
	var U := Vector2(0, -1)
	draw_colored_polygon(_diamond_shadow(base, 14.0), Color(0, 0, 0, 0.18))
	draw_line(base, base + U * 10, Color(0.34, 0.22, 0.12), 4.0)
	var green := Color(0.22, 0.44, 0.26)
	for k in range(3):
		var yy := 10.0 + k * 14.0
		var ww := 20.0 - k * 5.0
		draw_colored_polygon(PackedVector2Array([
			base + U * yy + Vector2(-ww, 0), base + U * (yy + 20.0), base + U * yy + Vector2(ww, 0)]), green)
		if snowy:
			draw_colored_polygon(PackedVector2Array([
				base + U * (yy + 12.0) + Vector2(-ww * 0.5, 0), base + U * (yy + 20.0),
				base + U * (yy + 12.0) + Vector2(ww * 0.5, 0)]), Color(0.95, 0.97, 1.0))


func _draw_rock(pos: Vector2) -> void:
	var base := Iso.project(pos)
	draw_colored_polygon(_diamond_shadow(base, 16.0), Color(0, 0, 0, 0.16))
	var theme := str(GameManager.current_town_def().get("theme", "desert"))
	var rc := Color(0.66, 0.38, 0.26) if theme == "canyon" else Color(0.55, 0.50, 0.46)
	draw_colored_polygon(_ellipse(base + Vector2(0, -8), 20, 12), rc)
	draw_colored_polygon(_ellipse(base + Vector2(8, -16), 12, 9), rc.lightened(0.1))
	draw_colored_polygon(_ellipse(base + Vector2(-10, -12), 9, 7), rc.darkened(0.1))


func _draw_bush(pos: Vector2) -> void:
	var base := Iso.project(pos)
	draw_colored_polygon(_diamond_shadow(base, 13.0), Color(0, 0, 0, 0.15))
	var g := Color(0.30, 0.50, 0.28)
	draw_colored_polygon(_ellipse(base + Vector2(0, -9), 16, 11), g)
	draw_colored_polygon(_ellipse(base + Vector2(-7, -14), 9, 8), g.lightened(0.08))
	draw_colored_polygon(_ellipse(base + Vector2(7, -13), 8, 7), g.darkened(0.06))


func _draw_skull(pos: Vector2) -> void:
	var base := Iso.project(pos)
	draw_colored_polygon(_diamond_shadow(base, 12.0), Color(0, 0, 0, 0.14))
	var bone := Color(0.92, 0.90, 0.82)
	draw_colored_polygon(_ellipse(base + Vector2(0, -8), 11, 9), bone)
	# Cornes.
	draw_line(base + Vector2(-9, -12), base + Vector2(-18, -16), bone, 3.0)
	draw_line(base + Vector2(9, -12), base + Vector2(18, -16), bone, 3.0)
	# Orbites + museau.
	draw_circle(base + Vector2(-4, -9), 2.0, Color(0.2, 0.18, 0.14))
	draw_circle(base + Vector2(4, -9), 2.0, Color(0.2, 0.18, 0.14))
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(-3, -4), base + Vector2(3, -4), base + Vector2(0, 0)]), Color(0.2, 0.18, 0.14))


func _draw_lamp_post(pos: Vector2) -> void:
	var base := Iso.project(pos)
	var U := Vector2(0, -1)
	draw_colored_polygon(_diamond_shadow(base, 10.0), Color(0, 0, 0, 0.16))
	draw_line(base, base + U * 44, Color(0.20, 0.16, 0.10), 3.0)
	var head := base + U * 46
	for i in range(4):
		draw_circle(head, 20.0 - i * 5, Color(1.0, 0.82, 0.40, 0.10))
	draw_colored_polygon(_ellipse(head, 5, 6), Color(0.30, 0.22, 0.12))
	draw_circle(head, 2.6, Color(1.0, 0.92, 0.6))


## Puits de la place centrale (margelle + toit).
func _draw_well() -> void:
	var b := Iso.project(WELL)
	draw_colored_polygon(_diamond_shadow(b, 30.0), Color(0, 0, 0, 0.2))
	# Margelle en pierre.
	draw_colored_polygon(_rect_diamond(Rect2(WELL.x - 26, WELL.y - 22, 52, 44)), Color(0.5, 0.46, 0.42))
	draw_polyline(_closed(_rect_diamond(Rect2(WELL.x - 26, WELL.y - 22, 52, 44))), Color(0.3, 0.28, 0.25), 2.0)
	draw_circle(b + Vector2(0, -8), 12.0, Color(0.12, 0.12, 0.16))
	# Poteaux + toit.
	draw_line(b + Vector2(-18, -10), b + Vector2(-18, -54), Color(0.4, 0.27, 0.15), 4.0)
	draw_line(b + Vector2(18, -10), b + Vector2(18, -54), Color(0.4, 0.27, 0.15), 4.0)
	draw_colored_polygon(PackedVector2Array([
		b + Vector2(-26, -52), b + Vector2(0, -66), b + Vector2(26, -52), b + Vector2(0, -44)]),
		Color(0.55, 0.30, 0.18))


## Diligence : 2 chevaux + chariot bâché + traînée de poussière.
func _draw_coach() -> void:
	# Poussière derrière (vers l'amont = nord).
	for i in range(3):
		var dp := Iso.project(_coach_pos - Vector2(0, 30.0 + i * 26.0))
		draw_circle(dp + Vector2(_rng.randf_range(-4, 4), -6), 9.0 - i * 2.0, Color(0.72, 0.6, 0.42, 0.22))
	# Attelage de 2 chevaux devant (vers l'aval = sud).
	_horse(_coach_pos + Vector2(-9, 44))
	_horse(_coach_pos + Vector2(10, 52))
	# Chariot bâché dessiné en volume.
	_draw_wagon(_coach_pos)


## Chariot bâché iso : caisse en bois (volume) + bâche en demi-cylindre + roues.
func _draw_wagon(pos: Vector2) -> void:
	draw_colored_polygon(_diamond_shadow(Iso.project(pos), 30.0), Color(0, 0, 0, 0.18))
	var fr := Rect2(pos.x - 24, pos.y - 16, 48, 32)
	var b0 := Iso.project(fr.position)
	var b1 := Iso.project(Vector2(fr.end.x, fr.position.y))
	var b2 := Iso.project(fr.end)
	var b3 := Iso.project(Vector2(fr.position.x, fr.end.y))
	var up := Vector2(0, -20)
	var wood := Color(0.45, 0.30, 0.16)
	draw_colored_polygon(PackedVector2Array([b1, b2, b2 + up, b1 + up]), wood.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([b3, b2, b2 + up, b3 + up]), wood)
	# Bâche (demi-cylindre beige) posée sur le dessus.
	var canvas := Color(0.88, 0.82, 0.68)
	var c0 := b3 + up
	var c1 := b2 + up
	var arch := PackedVector2Array([c0])
	for i in range(9):
		var u := float(i) / 8.0
		arch.append(c0.lerp(c1, u) + Vector2(0, -sin(u * PI) * 24.0))
	arch.append(c1)
	draw_colored_polygon(arch, canvas)
	draw_polyline(arch, canvas.darkened(0.18), 1.5)
	# Roues sur la face sud.
	for wp in [b3 + Vector2(7, -1), b2 + Vector2(-7, -1)]:
		draw_circle(wp, 7.0, Color(0.14, 0.09, 0.06))
		draw_circle(wp, 3.0, wood.lightened(0.1))


## Tonneau en bois : douves galbées, cerclages, dessus elliptique (volume iso).
func _draw_barrel(pos: Vector2) -> void:
	var base := Iso.project(pos)
	draw_colored_polygon(_diamond_shadow(base, 14.0), Color(0, 0, 0, 0.18))
	var h := 34.0
	var w := 13.0
	var bulge := 3.0
	var top := base + Vector2(0, -h)
	var wood := Color(0.52, 0.34, 0.18)
	# Corps galbé (gauche sombre, droite claire).
	var bodyL := PackedVector2Array([
		base + Vector2(-w, 0), base + Vector2(-w - bulge, -h * 0.5), base + Vector2(-w, -h),
		top, base + Vector2(0, 0)])
	draw_colored_polygon(bodyL, wood.darkened(0.18))
	var bodyR := PackedVector2Array([
		base + Vector2(0, 0), top, base + Vector2(w, -h),
		base + Vector2(w + bulge, -h * 0.5), base + Vector2(w, 0)])
	draw_colored_polygon(bodyR, wood)
	# Douves verticales.
	for sx in [-0.5, 0.0, 0.5]:
		draw_line(base + Vector2(w * sx, -2), base + Vector2(w * sx, -h + 2), wood.darkened(0.3), 1.0)
	# Cerclages métalliques.
	for cy in [-3.0, -h * 0.5, -h + 3.0]:
		var ww: float = w + bulge * (1.0 - abs((cy + h * 0.5) / (h * 0.5))) if cy != -h * 0.5 else w + bulge
		draw_line(base + Vector2(-ww, cy), base + Vector2(ww, cy), Color(0.30, 0.22, 0.16), 2.0)
	# Dessus (ellipse) + planches.
	draw_circle(top, 1.0, wood)
	var lid := PackedVector2Array()
	for i in range(13):
		var a := TAU * float(i) / 12.0
		lid.append(top + Vector2(cos(a) * w, sin(a) * w * 0.42))
	draw_colored_polygon(lid, wood.lightened(0.12))
	draw_polyline(lid, wood.darkened(0.3), 1.0)
	draw_line(top + Vector2(-w, 0), top + Vector2(w, 0), wood.darkened(0.25), 1.0)


## Cactus saguaro : tronc + deux bras, vert, avec épines et fleur.
func _draw_cactus(pos: Vector2) -> void:
	var base := Iso.project(pos)
	draw_colored_polygon(_diamond_shadow(base, 16.0), Color(0, 0, 0, 0.16))
	var green := Color(0.30, 0.50, 0.28)
	var dark := green.darkened(0.22)
	var tw := 8.0
	var th := 56.0
	var top := base + Vector2(0, -th)
	# Tronc (capsule).
	draw_line(base + Vector2(0, -tw), top, dark, tw * 2.0 + 2.0)
	draw_line(base + Vector2(0, -tw), top, green, tw * 2.0 - 2.0)
	draw_circle(top, tw - 1.0, green)
	# Bras gauche et droit (montent puis se redressent).
	var lj := base + Vector2(-1, -th * 0.45)       # jonction bras gauche
	draw_line(lj, lj + Vector2(-13, 0), green, tw + 3.0)
	draw_line(lj + Vector2(-13, 0), lj + Vector2(-13, -16), green, tw)
	draw_circle(lj + Vector2(-13, -16), tw * 0.5 + 1.0, green)
	var rj := base + Vector2(1, -th * 0.62)        # jonction bras droit
	draw_line(rj, rj + Vector2(12, 0), green, tw + 2.0)
	draw_line(rj + Vector2(12, 0), rj + Vector2(12, -20), green, tw - 1.0)
	draw_circle(rj + Vector2(12, -20), tw * 0.5, green)
	# Côtes verticales + petites épines.
	for sx in [-3.0, 0.0, 3.0]:
		draw_line(base + Vector2(sx, -tw), top + Vector2(sx * 0.6, 2), dark, 1.0)
	# Fleur rouge au sommet.
	draw_circle(top + Vector2(0, -1), 3.0, Color(0.85, 0.30, 0.28))


## Barre d'attache (poteaux + traverse) derrière les chevaux de l'écurie.
func _draw_hitch() -> void:
	var a := Iso.project(Vector2(1335, 1012))
	var b := Iso.project(Vector2(1545, 1012))
	var wood := Color(0.40, 0.27, 0.15)
	draw_line(a, a + Vector2(0, -26), wood, 4.0)
	draw_line(b, b + Vector2(0, -26), wood, 4.0)
	draw_line(a + Vector2(0, -22), b + Vector2(0, -22), wood, 4.0)


## Cheval vu de profil (regarde vers la gauche) : corps, pattes, queue, encolure,
## tête, crinière. Dessiné proprement (plus de "patate").
func _horse(world_pos: Vector2) -> void:
	var base := Iso.project(world_pos)
	draw_colored_polygon(_diamond_shadow(base, 18.0), Color(0, 0, 0, 0.18))
	var body := Color(0.36, 0.23, 0.13)
	var dark := body.darkened(0.28)
	# Pattes (4) — dessinées avant le corps.
	for dx in [-9.0, -3.0, 4.0, 10.0]:
		draw_line(base + Vector2(dx, -12), base + Vector2(dx + 1.0, 2), dark, 3.0)
	# Corps (capsule horizontale).
	var bl := base + Vector2(-12, -16)
	var brr := base + Vector2(12, -16)
	draw_line(bl, brr, body, 14.0)
	draw_circle(bl, 7.0, body)
	draw_circle(brr, 7.0, body)
	# Queue.
	draw_line(brr + Vector2(3, -3), base + Vector2(18, 3), dark, 3.0)
	# Encolure + tête (vers la gauche).
	var neck := bl + Vector2(1, -3)
	var head := bl + Vector2(-11, -16)
	draw_line(neck, head, body, 7.0)
	draw_circle(head, 4.5, body)
	draw_line(head, head + Vector2(-5, 2), body, 5.0)        # museau
	draw_line(head + Vector2(1, -3), head + Vector2(3, -7), body, 2.0)  # oreille
	draw_line(neck + Vector2(-1, -3), head + Vector2(3, 3), dark, 3.0)  # crinière
	draw_circle(head + Vector2(-2, -1), 1.0, Color(0.05, 0.04, 0.03))   # œil


## Style visuel par commerce (inspiré des décors western d'Almería) : murs en
## plâtre clair ou bois, volets/portes colorés, 1 ou 2 étages avec galerie.
func _building_style(label: String) -> Dictionary:
	match label:
		"★ BANQUE ★": return {"wall": Color(0.90, 0.86, 0.74), "trim": Color(0.45, 0.30, 0.16),
			"door": Color(0.20, 0.13, 0.08), "shutter": Color(0.30, 0.40, 0.55), "stories": 2, "plaster": true}
		"SALOON": return {"wall": Color(0.86, 0.50, 0.42), "trim": Color(0.40, 0.18, 0.12),
			"door": Color(0.30, 0.18, 0.10), "shutter": Color(0.85, 0.80, 0.70), "stories": 2}
		"HÔTEL": return {"wall": Color(0.84, 0.82, 0.76), "trim": Color(0.42, 0.28, 0.16),
			"door": Color(0.25, 0.35, 0.50), "shutter": Color(0.30, 0.45, 0.60), "stories": 2}
		"MAGASIN": return {"wall": Color(0.74, 0.55, 0.34), "trim": Color(0.40, 0.26, 0.14),
			"door": Color(0.30, 0.45, 0.35), "shutter": Color(0.55, 0.40, 0.22), "stories": 1}
		"ÉGLISE": return {"wall": Color(0.92, 0.90, 0.84), "trim": Color(0.40, 0.27, 0.15),
			"door": Color(0.30, 0.20, 0.10), "shutter": Color(0.6, 0.5, 0.35), "stories": 1, "cross": true, "plaster": true}
		"SHÉRIF": return {"wall": Color(0.78, 0.80, 0.82), "trim": Color(0.35, 0.30, 0.26),
			"door": Color(0.22, 0.16, 0.12), "shutter": Color(0.35, 0.42, 0.50), "stories": 1, "star": true}
		"ÉCURIE": return {"wall": Color(0.55, 0.40, 0.24), "trim": Color(0.32, 0.21, 0.11),
			"door": Color(0.14, 0.09, 0.05), "shutter": Color(0.42, 0.30, 0.16), "stories": 1, "bigdoor": true}
		"POSTE": return {"wall": Color(0.86, 0.82, 0.66), "trim": Color(0.40, 0.27, 0.15),
			"door": Color(0.30, 0.45, 0.35), "shutter": Color(0.35, 0.55, 0.40), "stories": 1}
		"FORGE": return {"wall": Color(0.50, 0.45, 0.42), "trim": Color(0.28, 0.24, 0.22),
			"door": Color(0.12, 0.10, 0.10), "shutter": Color(0.45, 0.35, 0.25), "stories": 1, "bigdoor": true}
		"DOCTEUR": return {"wall": Color(0.90, 0.89, 0.85), "trim": Color(0.42, 0.28, 0.16),
			"door": Color(0.55, 0.22, 0.18), "shutter": Color(0.70, 0.25, 0.22), "stories": 1, "redcross": true, "plaster": true}
		_: return {"wall": Color(0.82, 0.78, 0.70), "trim": Color(0.42, 0.28, 0.16),
			"door": Color(0.24, 0.16, 0.10), "shutter": Color(0.45, 0.40, 0.30), "stories": 1}


## Banque du Far West "grandeur nature" : façade en pierre de taille, deux
## pilastres cannelés, perron, double porte à imposte, fronton triangulaire avec
## horloge, corniche à denticules, fenêtres hautes à barreaux et nom doré gravé.
func _draw_bank(b: Dictionary) -> void:
	var fr: Rect2 = b["foot"]
	var U := Vector2(0, -1)
	var stone := Color(0.82, 0.74, 0.57)
	var side := stone.darkened(0.24)
	var roof := stone.darkened(0.34)
	var trim := Color(0.54, 0.43, 0.29)
	var gold := Color(0.95, 0.80, 0.34)
	var door := Color(0.24, 0.14, 0.08)
	var glass := Color(0.58, 0.73, 0.80)
	var gh := 92.0           # rez-de-chaussée
	var uh := 74.0           # étage
	var corn := 26.0         # entablement / corniche
	var body := gh + uh
	var total := body + corn
	var b0 := Iso.project(fr.position)
	var b1 := Iso.project(Vector2(fr.end.x, fr.position.y))
	var b2 := Iso.project(fr.end)
	var b3 := Iso.project(Vector2(fr.position.x, fr.end.y))
	var fL := b3
	var fR := b2
	var ax := fR - fL        # vecteur façade (gauche->droite), suit la rotation
	# Ombre portée.
	draw_colored_polygon(PackedVector2Array([b0 + Vector2(4, 4), b1 + Vector2(4, 4),
		b2 + Vector2(4, 4), b3 + Vector2(4, 4)]), Color(0, 0, 0, 0.20))
	# Volume : côté est + toit plat.
	draw_colored_polygon(PackedVector2Array([b1, b2, b2 + U * total, b1 + U * total]), side)
	_stone_courses(b1, b2, U, 0.0, body, side)
	# Détail du flanc est (visible quand on pivote la vue) : fenêtres à barreaux.
	var sx := b2 - b1
	var sglass := glass.darkened(0.12)
	_facequad(b1, b2, U, 0.0, 1.0, body, body + 16.0, trim.darkened(0.12))   # frise latérale
	for swu in [0.22, 0.5, 0.78]:
		_bank_win(b1, b2, sx, U, swu, 0.06, gh + 18.0, body - 16.0, sglass, trim, gold, false)
	_bank_win(b1, b2, sx, U, 0.30, 0.075, gh * 0.30, gh * 0.74, sglass, trim, gold, true)
	_bank_win(b1, b2, sx, U, 0.70, 0.075, gh * 0.30, gh * 0.74, sglass, trim, gold, true)
	var r0 := b0 + U * body
	var r1 := b1 + U * body
	var r2 := b2 + U * body
	var r3 := b3 + U * body
	draw_colored_polygon(PackedVector2Array([r0, r1, r2, r3]), roof)
	# Toiture habillée (visible en vue pivotée) : voliges + parapet.
	for t in [0.25, 0.5, 0.75]:
		draw_line(r0.lerp(r1, t), r3.lerp(r2, t), roof.darkened(0.10), 1.0)
		draw_line(r0.lerp(r3, t), r1.lerp(r2, t), roof.lightened(0.04), 1.0)
	draw_polyline(PackedVector2Array([r0, r1, r2, r3, r0]), roof.darkened(0.22), 2.0)
	# Petite verrière de toit (lanterneau).
	var lc := (r0 + r1 + r2 + r3) * 0.25
	draw_colored_polygon(PackedVector2Array([
		lc + Vector2(-12, -2), lc + Vector2(12, -2), lc + Vector2(12, -16), lc + Vector2(-12, -16)]),
		glass.darkened(0.05))
	draw_rect(Rect2(lc + Vector2(-12, -16), Vector2(24, 14)), trim, false, 1.5)
	draw_line(lc + Vector2(0, -2), lc + Vector2(0, -16), trim, 1.0)
	# Façade pierre + appareillage.
	draw_colored_polygon(PackedVector2Array([fL, fR, fR + U * total, fL + U * total]), stone)
	_stone_courses(fL, fR, U, 0.0, body, stone)
	# Soubassement plus sombre.
	_facequad(fL, fR, U, 0.0, 1.0, 0.0, 15.0, stone.darkened(0.18))
	# Bandeau d'étage.
	_facequad(fL, fR, U, 0.0, 1.0, gh - 6.0, gh, trim)

	# Deux pilastres encadrant l'entrée.
	for cu in [0.30, 0.70]:
		_facequad(fL, fR, U, cu - 0.035, cu + 0.035, 0.0, body, stone.lightened(0.05))
		draw_line(fL.lerp(fR, cu + 0.035), fL.lerp(fR, cu + 0.035) + U * body, stone.darkened(0.22), 1.0)
		draw_line(fL.lerp(fR, cu - 0.035), fL.lerp(fR, cu - 0.035) + U * body, stone.darkened(0.08), 1.0)
		for fu in [-0.014, 0.0, 0.014]:                       # cannelures
			draw_line(fL.lerp(fR, cu + fu) + U * 16, fL.lerp(fR, cu + fu) + U * (gh - 14), stone.darkened(0.13), 1.0)
		_facequad(fL, fR, U, cu - 0.05, cu + 0.05, gh - 16, gh - 4, trim)   # chapiteau
		_facequad(fL, fR, U, cu - 0.05, cu + 0.05, 2.0, 14.0, trim)          # base

	# Fenêtres hautes à barreaux (rez-de-chaussée).
	_bank_win(fL, fR, ax, U, 0.155, 0.085, gh * 0.30, gh * 0.74, glass, trim, gold, true)
	_bank_win(fL, fR, ax, U, 0.845, 0.085, gh * 0.30, gh * 0.74, glass, trim, gold, true)
	# Fenêtres de l'étage.
	for wu in [0.20, 0.5, 0.80]:
		_bank_win(fL, fR, ax, U, wu, 0.065, gh + 18.0, body - 16.0, glass, trim, gold, false)

	# Entrée : encadrement + double porte + imposte en éventail.
	_facequad(fL, fR, U, 0.40, 0.60, 0.0, gh * 0.70, trim)
	_facequad(fL, fR, U, 0.415, 0.585, 0.0, gh * 0.64, door)
	draw_line(fL.lerp(fR, 0.5), fL.lerp(fR, 0.5) + U * (gh * 0.62), trim.darkened(0.2), 1.5)
	for pv in [0.16, 0.40, 0.62]:                             # panneaux dorés
		draw_line(fL.lerp(fR, 0.43) + U * (gh * pv), fL.lerp(fR, 0.57) + U * (gh * pv), gold.darkened(0.1), 1.0)
	draw_circle(fL.lerp(fR, 0.47) + U * (gh * 0.34), 1.6, gold)
	draw_circle(fL.lerp(fR, 0.53) + U * (gh * 0.34), 1.6, gold)
	# Imposte en éventail au-dessus de la porte.
	var fan := fL.lerp(fR, 0.5) + U * (gh * 0.70)
	var fanpts := PackedVector2Array([fL.lerp(fR, 0.41) + U * (gh * 0.70)])
	for i in range(11):
		var a := PI * float(i) / 10.0
		fanpts.append(fan + ax * 0.09 * cos(a) + U * (22.0 * sin(a)))
	fanpts.append(fL.lerp(fR, 0.59) + U * (gh * 0.70))
	draw_colored_polygon(fanpts, glass.lightened(0.05))
	for i in range(1, 6):
		var a2 := PI * float(i) / 6.0
		draw_line(fan, fan + ax * 0.09 * cos(a2) + U * (22.0 * sin(a2)), trim, 1.0)

	# Petit auvent (portique) au-dessus de l'entrée, posé sur les pilastres.
	var pout := Vector2(0, 16)
	var pL := fL.lerp(fR, 0.27) + U * (gh * 0.86)
	var pR := fL.lerp(fR, 0.73) + U * (gh * 0.86)
	draw_colored_polygon(PackedVector2Array([pL, pR, pR + pout, pL + pout]), trim.darkened(0.06))
	draw_line(pL + pout, pR + pout, trim.darkened(0.3), 2.0)

	# Perron : deux marches de pierre devant la porte.
	for i in range(2):
		var w := 0.13 + i * 0.035
		var off := Vector2(0, 6.0 + i * 6.0)
		var sa := fL.lerp(fR, 0.5 - w) + off
		var sc := fL.lerp(fR, 0.5 + w) + off
		draw_colored_polygon(PackedVector2Array([sa, sc, sc + Vector2(0, 6), sa + Vector2(0, 6)]),
			stone.darkened(0.06 + i * 0.06))

	# Entablement : architrave + frise (nom gravé) + corniche à denticules.
	draw_line(fL + U * body, fR + U * body, trim, 2.0)
	_facequad(fL, fR, U, 0.0, 1.0, body, body + 16.0, trim.darkened(0.06))
	for i in range(1, 22):                                    # denticules
		var du := float(i) / 22.0
		_facequad(fL, fR, U, du - 0.012, du + 0.012, body + 16.0, body + 22.0, stone.lightened(0.04))
	_facequad(fL, fR, U, 0.0, 1.0, body + 22.0, total, stone.darkened(0.04))
	var name_c := (fL.lerp(fR, 0.5)) + U * (body + 5.0)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, name_c - Vector2(38, 0), "BANQUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0, 0, 0))
	draw_string(font, name_c - Vector2(38, 0), "BANQUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, gold)

	# Fronton triangulaire avec horloge.
	var apex := fL.lerp(fR, 0.5) + U * (total + 34.0)
	var pedL := fL.lerp(fR, 0.18) + U * total
	var pedR := fL.lerp(fR, 0.82) + U * total
	draw_colored_polygon(PackedVector2Array([pedL, pedR, apex]), stone.lightened(0.04))
	draw_polyline(PackedVector2Array([pedL, apex, pedR]), trim.darkened(0.1), 2.0)
	var clock := fL.lerp(fR, 0.5) + U * (total + 13.0)
	draw_circle(clock, 8.5, Color(0.95, 0.92, 0.82))
	draw_arc(clock, 8.5, 0, TAU, 18, trim, 1.5)
	draw_line(clock, clock + Vector2(0, -5), trim.darkened(0.3), 1.5)
	draw_line(clock, clock + Vector2(4, 1), trim.darkened(0.3), 1.5)

	# Lanternes de part et d'autre de la porte.
	_lantern(fL.lerp(fR, 0.355) + U * (gh * 0.62))
	_lantern(fL.lerp(fR, 0.645) + U * (gh * 0.62))


## Appareillage en pierre de taille (assises + joints décalés).
func _stone_courses(L: Vector2, R: Vector2, U: Vector2, v0: float, v1: float, base: Color) -> void:
	var rows := 8
	for i in range(1, rows):
		var vy := lerpf(v0, v1, float(i) / rows)
		draw_line(L + U * vy, R + U * vy, base.darkened(0.16), 1.0)
	for i in range(rows):
		var a := lerpf(v0, v1, float(i) / rows)
		var c := lerpf(v0, v1, float(i + 1) / rows)
		var u := 0.07 if i % 2 == 0 else 0.14
		while u < 0.94:
			draw_line(L.lerp(R, u) + U * a, L.lerp(R, u) + U * c, base.darkened(0.12), 1.0)
			u += 0.14


## Fenêtre de banque : encadrement de pierre, vitre froide, clé de voûte, barreaux.
func _bank_win(L: Vector2, R: Vector2, ax: Vector2, U: Vector2, u: float, half: float,
		v0: float, v1: float, glass: Color, trim: Color, gold: Color, bars: bool) -> void:
	var c := L.lerp(R, u) + U * ((v0 + v1) * 0.5)
	draw_circle(c, 13.0, Color(0.80, 0.86, 0.95, 0.10))            # léger reflet
	_facequad(L, R, U, u - half - 0.012, u + half + 0.012, v0 - 3, v1 + 2, trim)  # cadre
	_facequad(L, R, U, u - half, u + half, v0, v1, glass)
	# Meneaux (4 carreaux).
	draw_line(L.lerp(R, u) + U * v0, L.lerp(R, u) + U * v1, trim.darkened(0.1), 1.0)
	draw_line(L.lerp(R, u - half) + U * ((v0 + v1) * 0.5), L.lerp(R, u + half) + U * ((v0 + v1) * 0.5), trim.darkened(0.1), 1.0)
	# Barreaux dorés.
	if bars:
		for k in [-0.5, 0.0, 0.5]:
			draw_line(L.lerp(R, u + half * k) + U * (v0 + 2), L.lerp(R, u + half * k) + U * (v1 - 2), gold.darkened(0.15), 1.0)
	# Clé de voûte + linteau.
	_facequad(L, R, U, u - half - 0.012, u + half + 0.012, v1 + 2, v1 + 8, trim.lightened(0.06))
	_facequad(L, R, U, u - 0.016, u + 0.016, v1 + 2, v1 + 11, trim.lightened(0.12))


## Bâtiment style "Almería" : murs plâtre/bois, étage + galerie sur poteaux,
## volets colorés, parapet, enseigne. Base = empreinte de collision exacte.
func _draw_building(b: Dictionary) -> void:
	if str(b["label"]) == "★ BANQUE ★":
		_draw_bank(b)
		return
	var fr: Rect2 = b["foot"]
	var s := _building_style(str(b["label"]))
	var wall: Color = s["wall"]
	var side := wall.darkened(0.24)
	var trim: Color = s["trim"]
	var two: bool = int(s.get("stories", 1)) >= 2
	var plaster: bool = bool(s.get("plaster", false))
	var U := Vector2(0, -1)
	var gh := 84.0                                   # rez-de-chaussée
	var uh := 74.0 if two else 0.0                   # étage
	var body := gh + uh
	var parapet := 15.0
	var total := body + parapet
	var b0 := Iso.project(fr.position)
	var b1 := Iso.project(Vector2(fr.end.x, fr.position.y))
	var b2 := Iso.project(fr.end)
	var b3 := Iso.project(Vector2(fr.position.x, fr.end.y))
	var fL := b3
	var fR := b2
	# Ombre.
	draw_colored_polygon(PackedVector2Array([b0 + Vector2(3, 3), b1 + Vector2(3, 3),
		b2 + Vector2(3, 3), b3 + Vector2(3, 3)]), Color(0, 0, 0, 0.18))
	# Côté est + dessus (volume).
	draw_colored_polygon(PackedVector2Array([b1, b2, b2 + U * total, b1 + U * total]), side)
	draw_colored_polygon(PackedVector2Array([
		b0 + U * body, b1 + U * body, b2 + U * body, b3 + U * body]), wall.darkened(0.32))
	# Façade + texture (bardage bois ou crépi).
	draw_colored_polygon(PackedVector2Array([fL, fR, fR + U * total, fL + U * total]), wall)
	_siding(fL, fR, U, 0.0, total, wall, plaster)
	# Parapet (corniche) + ligne.
	draw_colored_polygon(PackedVector2Array([
		fL + U * body, fR + U * body, fR + U * total, fL + U * total]), wall.darkened(0.12))
	draw_line(fL + U * body, fR + U * body, trim.lightened(0.1), 1.5)
	# Symboles optionnels (croix, étoile).
	var topc := (fL + fR) * 0.5 + U * (total + 10.0)
	if s.get("cross", false) or s.get("redcross", false):
		var cc: Color = Color(0.7, 0.2, 0.18) if s.get("redcross", false) else trim
		draw_line(topc, topc + U * 12, cc, 3.0)
		draw_line(topc + U * 8 + Vector2(-5, 0), topc + U * 8 + Vector2(5, 0), cc, 3.0)

	# --- Étage : galerie (balcon) sur poteaux ---
	var out := Vector2(0, 18)
	if two:
		var av := gh + 4.0
		# Plancher du balcon (déborde vers la rue) + bord.
		draw_colored_polygon(PackedVector2Array([
			fL + U * av, fR + U * av, fR + U * av + out, fL + U * av + out]), trim.darkened(0.05))
		draw_line(fL + U * av + out, fR + U * av + out, trim.darkened(0.25), 2.0)
		# Garde-corps du balcon.
		draw_line(fL + U * (av + 22) + out, fR + U * (av + 22) + out, trim, 2.0)
		for r in range(1, 12):
			var ru := float(r) / 12.0
			var rp := (fL + out).lerp(fR + out, ru)
			draw_line(rp + U * av, rp + U * (av + 22), trim, 1.0)
		# Fenêtres + porte de l'étage.
		for wx in [0.22, 0.78]:
			_win2(fL, fR, U, wx, av + 30, av + uh - 8, trim, s["shutter"])
		_facequad(fL, fR, U, 0.44, 0.56, av + 26, av + uh - 6, s["door"])
		# Poteaux de la galerie (du sol au balcon).
		for pu in [0.07, 0.5, 0.93]:
			var pf := fL.lerp(fR, pu) + out
			draw_line(pf, pf + U * av, trim.darkened(0.1), 3.5)
		_lantern(fL.lerp(fR, 0.07) + out + U * (av - 12.0))
	else:
		# 1 étage : auvent sur poteaux.
		var av := gh * 0.86
		draw_colored_polygon(PackedVector2Array([
			fL + U * av, fR + U * av, fR + U * av + out, fL + U * av + out]), trim.darkened(0.08))
		draw_line(fL + U * av + out, fR + U * av + out, trim.darkened(0.25), 2.0)
		for pu in [0.08, 0.92]:
			var pf := fL.lerp(fR, pu) + out
			draw_line(pf, pf + U * av, trim.darkened(0.1), 3.0)
		_lantern(fL.lerp(fR, 0.08) + out + U * (av - 10.0))

	# --- Rez-de-chaussée : porte + fenêtres/volets ---
	if s.get("bigdoor", false):
		_facequad(fL, fR, U, 0.30, 0.70, 0.0, gh * 0.78, trim.darkened(0.15))
		_facequad(fL, fR, U, 0.33, 0.67, 0.0, gh * 0.72, s["door"])
		draw_line(fL.lerp(fR, 0.5) + U * 2, fL.lerp(fR, 0.5) + U * (gh * 0.72), trim, 1.5)
	else:
		# Porte centrale.
		_facequad(fL, fR, U, 0.42, 0.58, 0.0, gh * 0.56, trim.darkened(0.1))
		_facequad(fL, fR, U, 0.445, 0.555, 0.0, gh * 0.52, s["door"])
		draw_circle(fL.lerp(fR, 0.535) + U * (gh * 0.26), 1.6, Color(0.85, 0.72, 0.3))
		# Fenêtres + volets de chaque côté.
		_win2(fL, fR, U, 0.2, gh * 0.22, gh * 0.5, trim, s["shutter"])
		_win2(fL, fR, U, 0.8, gh * 0.22, gh * 0.5, trim, s["shutter"])

	# Enseigne accrochée sous l'auvent.
	var sy: float = (gh + 4.0) if two else (gh * 0.86)
	_sign((fL + fR) * 0.5 + out + U * (sy - 6.0), b["label"])


## Fenêtre à carreaux éclairée (halo chaud) + 2 volets ouverts.
func _win2(L: Vector2, R: Vector2, U: Vector2, u: float, v0: float, v1: float,
		frame: Color, shutter: Color) -> void:
	var c := L.lerp(R, u) + U * ((v0 + v1) * 0.5)
	# Lueur chaude derrière la vitre (vie + ambiance crépusculaire).
	draw_circle(c, 12.0, Color(1.0, 0.78, 0.38, 0.10))
	draw_circle(c, 7.5, Color(1.0, 0.82, 0.42, 0.16))
	_facequad(L, R, U, u - 0.13, u - 0.075, v0, v1, shutter)              # volet gauche
	_facequad(L, R, U, u + 0.075, u + 0.13, v0, v1, shutter)             # volet droit
	_facequad(L, R, U, u - 0.075, u + 0.075, v0 - 2, v1 + 2, frame)      # cadre
	_facequad(L, R, U, u - 0.06, u + 0.06, v0, v1, Color(1.0, 0.86, 0.52))  # vitre éclairée
	var mv := (v0 + v1) * 0.5
	draw_line(L.lerp(R, u) + U * v0, L.lerp(R, u) + U * v1, frame, 1.0)
	draw_line(L.lerp(R, u - 0.06) + U * mv, L.lerp(R, u + 0.06) + U * mv, frame, 1.0)


## Bardage : planches verticales nuancées (bois) ou crépi lisse (plâtre).
func _siding(L: Vector2, R: Vector2, U: Vector2, v0: float, v1: float,
		base: Color, plaster: bool) -> void:
	if plaster:
		for k in range(1, 4):
			var vy := lerpf(v0, v1, float(k) / 4.0)
			draw_line(L + U * vy, R + U * vy, base.darkened(0.06), 1.0)
		return
	var n := 9
	for i in range(n):
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		var shade := base.darkened(0.04) if i % 2 == 0 else base.darkened(0.12)
		_facequad(L, R, U, u0, u1, v0, v1, shade)
		draw_line(L.lerp(R, u1) + U * v0, L.lerp(R, u1) + U * v1, base.darkened(0.30), 1.0)
	for f in [0.34, 0.67]:
		var vy := lerpf(v0, v1, f)
		draw_line(L + U * vy, R + U * vy, base.darkened(0.20), 1.0)


## Lanterne chaude accrochée à un poteau du porche.
func _lantern(pos: Vector2) -> void:
	draw_circle(pos, 9.0, Color(1.0, 0.74, 0.30, 0.10))
	draw_circle(pos, 5.5, Color(1.0, 0.80, 0.36, 0.16))
	draw_line(pos + Vector2(0, -10), pos + Vector2(0, -5), Color(0.18, 0.12, 0.07), 1.5)
	draw_rect(Rect2(pos - Vector2(2.5, 4.5), Vector2(5, 9)), Color(0.22, 0.14, 0.07))
	draw_circle(pos, 2.4, Color(1.0, 0.9, 0.55))


## Quad sur une face verticale (L,R base ; up unitaire ; v en pixels).
func _facequad(L: Vector2, R: Vector2, U: Vector2, u0: float, u1: float,
		v0: float, v1: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		L.lerp(R, u0) + U * v0, L.lerp(R, u1) + U * v0,
		L.lerp(R, u1) + U * v1, L.lerp(R, u0) + U * v1]), col)


func _tinted(base: Color, tint: Color) -> Color:
	return Color(base.r * tint.r, base.g * tint.g, base.b * tint.b)


func _sign(center: Vector2, label: String) -> void:
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16
	var r := Rect2(center - Vector2(w * 0.5, 11), Vector2(w, 22))
	# Chaînes de suspension.
	draw_line(Vector2(r.position.x + 5, r.position.y), Vector2(r.position.x + 5, r.position.y - 8),
			Color(0.14, 0.10, 0.06), 1.5)
	draw_line(Vector2(r.end.x - 5, r.position.y), Vector2(r.end.x - 5, r.position.y - 8),
			Color(0.14, 0.10, 0.06), 1.5)
	# Plaque en bois.
	draw_rect(r, Color(0.28, 0.18, 0.09))
	draw_rect(Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)), Color(0.40, 0.26, 0.13), false, 1.0)
	draw_rect(r, Color(0.62, 0.46, 0.26), false, 2.0)
	draw_string(font, center - Vector2(w * 0.5 - 8, -4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(0.99, 0.93, 0.72))


func _sand_tile(x: float, y: float, w: float, h: float) -> void:
	var pts := PackedVector2Array([
		Iso.project(Vector2(x, y)), Iso.project(Vector2(x + w, y)),
		Iso.project(Vector2(x + w, y + h)), Iso.project(Vector2(x, y + h))])
	var p := R_SAND.position
	var s := R_SAND.size
	var uvs := PackedVector2Array([
		p / TEX, Vector2(p.x + s.x, p.y) / TEX,
		Vector2(p.x + s.x, p.y + s.y) / TEX, Vector2(p.x, p.y + s.y) / TEX])
	draw_colored_polygon(pts, Color.WHITE, uvs, SHEET)


func _billboard(region: Rect2, world_pos: Vector2, target_h: float, tint: Color) -> void:
	var base := Iso.project(world_pos)
	var aspect := region.size.x / region.size.y
	var h := target_h
	var w := h * aspect
	draw_colored_polygon(_diamond_shadow(base, w * 0.34), Color(0, 0, 0, 0.18))
	draw_texture_rect_region(SHEET, Rect2(base.x - w * 0.5, base.y - h, w, h), region, tint)


func _draw_me() -> void:
	var f := _screen_facing(_player_pos, _facing)
	CharacterArt.draw_person(self, Iso.project(_player_pos), f, CharacterArt.hero_palette(),
			false, false, _walk, 0.0, 0.0)


func _screen_facing(world_pos: Vector2, facing: Vector2) -> Vector2:
	var f := Iso.project(world_pos + facing) - Iso.project(world_pos)
	return f.normalized() if f.length() > 0.001 else Vector2.DOWN


# --- Primitives ---

func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _rect_diamond(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		Iso.project(r.position), Iso.project(Vector2(r.end.x, r.position.y)),
		Iso.project(r.end), Iso.project(Vector2(r.position.x, r.end.y))])


func _diamond_shadow(center: Vector2, rx: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-rx, 0), center + Vector2(0, -rx * 0.5),
		center + Vector2(rx, 0), center + Vector2(0, rx * 0.5)])


func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var c := poly.duplicate()
	if c.size() > 0:
		c.append(c[0])
	return c


func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# --- UI (titre + bouton retour + contrôles tactiles + bandeau d'ambiance) ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2                  # au-dessus du voile d'ambiance (vignette = 1)
	add_child(layer)
	get_viewport().size_changed.connect(_on_viewport_resized)

	var title := Label.new()
	title.text = "%s — explore la ville · clique le logo près des portes/gens (ou E)" % str(GameManager.current_town_def().get("name", "EL DORADO"))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 4)
	title.position = Vector2(16, 12)
	layer.add_child(title)

	var back := Button.new()
	back.text = "← Carte"
	back.add_theme_font_size_override("font_size", 20)
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.position = Vector2(-150, 12)
	back.custom_minimum_size = Vector2(130, 44)
	back.pressed.connect(func() -> void: GameManager.goto_world_map())
	layer.add_child(back)

	# Boutons de rotation de la vue (desktop + mobile) : tournent le décor de 45°.
	var rot := HBoxContainer.new()
	rot.add_theme_constant_override("separation", 8)
	rot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rot.position = Vector2(-150, 64)
	for spec in [["⟲", -1], ["⟳", 1]]:
		var rb := Button.new()
		rb.text = str(spec[0])
		rb.add_theme_font_size_override("font_size", 24)
		rb.custom_minimum_size = Vector2(61, 44)
		rb.focus_mode = Control.FOCUS_NONE
		var st: int = spec[1]
		rb.pressed.connect(func() -> void: _rotate_view(st))
		rot.add_child(rb)
	layer.add_child(rot)

	# Bandeau d'ambiance (texte affiché en bas quand on observe un lieu).
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

	# Mobile : joystick seul (l'action passe par le logo cliquable près des portes).
	var mc := Control.new()
	mc.set_script(load("res://scripts/mobile_controls.gd"))
	mc.set("combat_buttons", false)
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(mc)

	# Pastille d'action contextuelle (apparaît devant la porte/cible, cliquable).
	_action_btn = _make_action_button()
	layer.add_child(_action_btn)


## Crée la pastille d'action (logo + libellé) cliquable.
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
	tw.tween_interval(2.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)
