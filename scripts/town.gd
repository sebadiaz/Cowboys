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
const FLOOR := Rect2(0, 0, 5300, 1500)
const TOWN_CENTER := Vector2(2170, 1150)   # la rue : les portes s'ouvrent vers elle (vers le bas)
const BANK_DOOR := Vector2(2170, 815)
const DOOR_RADIUS := 95.0
const PLAYER_RADIUS := 15.0
const TALK_RADIUS := 95.0
const WELL := Vector2(2170, 1330)
const TOWN_RETURN_MAGASIN := Vector2(760, 1360)   # réapparition devant le Magasin

var _player_pos := Vector2(2170, 1130)
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
var _shopping := false                # boutique ouverte EN OVERLAY (lot intérieurs)
var _shop_layer: CanvasLayer
var _shop_cat := ""
var _shop_rows: VBoxContainer
var _shop_money: Label
var _horses: Array[Vector2] = []     # chevaux attachés (décor solide + à monter)
var _horse_ctrl := HorseController.new()   # monture du joueur (lot 16)
var _ride_walk := 0.0                # phase de galop (balancement du cavalier)
var _wanted := WantedSystem.new()    # chasseurs de primes (lot 14)
var _wanted_label: Label             # bandeau "PRIME / chasseurs" (CanvasLayer)
var _bank_center := Vector2(2170, 680)   # centre de la banque (placement séquentiel)
# Braquage de banque IN-MAP (même plan, linéaire) : on force le coffre dans le
# hall, l'alarme sonne, la loi débarque, on file par la rue.
var _vault_cracking := false
var _vault_prog := 0.0
var _heist_done := false
var _posse: Array[Dictionary] = []   # lois lancées à ta poursuite {pos, facing}
var _escape_t := 0.0
var _posse_grace := 0.0              # répit juste après le coffre (le temps de filer)
const LAWMAN_SPEED := 178.0
# Combat in-map du braquage : alarme + gardes qui ripostent dans le hall.
var _alarm_on := false
var _bank_guards: Array[Dictionary] = []   # {pos, facing, hp, alive, fire_cd}
var _town_bullets: Array[Dictionary] = []  # {pos, vel, friendly, life}
var _php := 5
var _pmax := 5
var _php_dmg_cd := 0.0
var _fire_cd := 0.0
var _muzzle_t := 0.0                 # flash de bouche
var _hp_label: Label
# Chasse libre : bandits qui rôdent + auto-visée/tir continu sur le plus proche.
var _bandits: Array[Dictionary] = []   # {pos, vel, hp, alive, fire_cd, wander_t, respawn}
var _floaters: Array[Dictionary] = []  # {pos, t, text, col} (pop-ups +$ / coups)
var _aim_target := Vector2.ZERO
var _has_target := false
var _bursts: Array[Dictionary] = []   # éclats de mort (sang/poussière) {pos, vel, t, col}
var _streak := 0                       # série de kills en cours (combo)
var _streak_t := 0.0                   # temps restant avant reset de la série
var _shake := 0.0                      # intensité de tremblement caméra (impact)
var _boss = null                       # mini-boss hors-la-loi RECHERCHÉ (null = aucun)
var _boss_timer := 26.0                # délai avant la prochaine apparition
var _rush_active := false              # RUÉE en cours (vague de bandits, primes ×2)
var _rush_t := 0.0                     # temps restant de la ruée
var _rush_cd := 40.0                   # délai avant la prochaine ruée
var _raid_active := false              # DESCENTE DE LA LOI (à haute notoriété)
var _raid_cd := 30.0                   # délai avant la prochaine descente
var _raid_left := 0                    # lois encore debout dans la descente
const RUSH_DURATION := 16.0
const RAID_MIN_NOTORIETY := 3
const BANDIT_SPEED := 125.0
const BOSS_SPEED := 168.0
const AUTO_RANGE := 460.0
const BOSS_NAMES := ["Black Jack McGraw", "El Cuervo", "Doc Holloway", "Sundance Kid",
	"Wild Bill Cassidy", "Coyote Malone"]
const STREAK_WINDOW := 3.2             # fenêtre pour enchaîner les kills
var _tumble: Array[Dictionary] = []  # tumbleweeds qui roulent (décor mobile)

const HORSE_LINES := ["Un fier mustang, prêt à filer après le coup.",
	"*hennissement* Doux, mon beau...", "Ce cheval ferait une belle monture de fuite."]

var _buildings: Array[Dictionary] = []   # {region,pos,h,label,tint,flavor,fade}
var _fade := 1.0   # opacité du bâtiment en cours de dessin (occlusion -> transparence)
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

# Diligence qui remonte la grand-rue (ambiance).
const COACH_A := Vector2(-150, 1250)
const COACH_B := Vector2(4500, 1250)
const COACH_SPEED := 200.0
var _coach_pos := COACH_A
var _coach_wait := 2.5
var _dust_t := 0.0


func _ready() -> void:
	_rng.randomize()
	Iso.yaw = 0.0
	_yaw_target = 0.0
	# Réapparition à la sortie du saloon (sinon, devant la banque).
	var has_return := GameManager.town_return_pos != Vector2.ZERO
	if has_return:
		_player_pos = GameManager.town_return_pos
		_facing = Vector2.DOWN
		GameManager.town_return_pos = Vector2.ZERO
	_build_town()
	if not has_return:
		_player_pos = _bank_center + Vector2(0, 430.0)   # spawn dans la rue, devant la banque
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
	# Calque "golden hour" : poussières d'or, halo de soleil, oiseaux, nuit étoilée.
	var atmo := Control.new()
	atmo.set_script(load("res://scripts/atmosphere.gd"))
	atmo.set_anchors_preset(Control.PRESET_FULL_RECT)
	atmo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(atmo)
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
	if _horse_ctrl.mounted:
		# À cheval : vitesse + inertie (le galop se lance et se freine).
		_body.velocity = _horse_ctrl.compute_velocity(delta, dir)
		_facing = _horse_ctrl.facing
		_ride_walk += delta * (4.0 + 14.0 * _horse_ctrl.gallop)
	else:
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
	# GRAND-RUE : une rangée de GROS bâtiments alignés en haut (y≈680), tous
	# tournés vers la rue (en bas). On longe la rue et on entre par la porte.
	# [region, label, bigger-foot, flavor, enter]
	var row := [
		[R_SHED,   "MAISON",     Vector2(210, 175), "Maison de ville — volets clos.", ""],
		[R_HOUSE,  "ÉGLISE",     Vector2(215, 178), "Église en bois — une prière avant le casse ?", ""],
		[R_HOUSE,  "HÔTEL",      Vector2(225, 182), "Hôtel de la Frontière — 2 $ la nuit.", ""],
		[R_SALOON, "SALOON",     Vector2(245, 195), "Saloon Le Cactus — entre boire un coup.", ""],
		[R_SHED,   "MAGASIN",    Vector2(225, 182), "Magasin général — bottes, crochets, sacoches.", "store"],
		[R_BANK,   "★ BANQUE ★", Vector2(440, 330), "", ""],   # LA PLUS GROSSE : on la braque
		[R_HOUSE,  "SHÉRIF",     Vector2(225, 182), "Bureau du shérif — file avant qu'il ne rentre.", ""],
		[R_SHED,   "FORGE",      Vector2(225, 182), "Armurier & forge — recharge, barillet, cadence.", "gunsmith"],
		[R_SHED,   "ÉCURIE",     Vector2(225, 182), "Écurie — ton cheval, prêt pour la fuite.", ""],
		[R_SALOON, "POSTE",      Vector2(225, 182), "Poste & télégraphe — « STOP braquage STOP ».", ""],
		[R_HOUSE,  "DOCTEUR",    Vector2(225, 182), "Cabinet du Doc — vitalité, tonique anti-balles.", "pharmacy"],
	]
	var ry := 700.0
	var tints := [Color(0.95,0.92,0.85), Color(0.95,0.95,1.0), Color(0.92,0.96,1.0),
		Color(1.0,0.92,0.9), Color(1.0,0.96,0.85), Color(1,1,1), Color(0.85,0.9,1.0),
		Color(1.0,0.9,0.8), Color(0.95,0.88,0.78), Color(0.9,1.0,0.9), Color(0.9,1.0,0.95)]
	# Placement SÉQUENTIEL par largeur (la grosse banque obtient automatiquement sa
	# place, sans chevaucher ses voisins). _add_building agrandit le footprint x1.35.
	var x := 300.0
	var margin := 110.0
	var ecurie_x := x
	var centers: Array[float] = []
	for i in range(row.size()):
		var e: Array = row[i]
		var w: float = (e[2] as Vector2).x * 1.35
		var cx := x + w * 0.5
		_add_building(e[0], Vector2(cx, ry), 200.0, e[1], tints[i], e[3], e[2], e[4])
		centers.append(cx)
		if e[1] == "★ BANQUE ★":
			_bank_center = Vector2(cx, ry)
		if e[1] == "ÉCURIE":
			ecurie_x = cx
		x += w + margin

	# Mobilier de rue (devant les bâtiments, sur la grand-rue y≈1000-1200).
	_add_prop(R_SIGN, Vector2(_bank_center.x, 1020.0), 100.0)   # panneau devant la banque
	for i in range(centers.size()):
		if i % 2 == 0:
			_add_prop(R_BARREL, Vector2(centers[i] - 100.0, 1030.0), 78.0)
		else:
			_add_prop(R_WAGON, Vector2(centers[i] + 40.0, 1150.0), 150.0)
	for c in [Vector2(180, 1380), Vector2(4150, 1360), Vector2(180, 380),
			Vector2(4150, 420), Vector2(2170, 1420)]:
		_add_prop(R_CACTUS, c, 130.0)

	# Habitants sur la grand-rue.
	var names := [
		["Vieux Hank", ["La banque ? Personne ne l'a jamais braquée...", "Le shérif a la gâchette facile."]],
		["Rosita", ["Tu as l'air d'un homme à histoires, étranger.", "Le coffre prend un moment à ouvrir."]],
		["Petit Joe", ["Wow, t'as vu son flingue ?!", "Un jour je serai un hors-la-loi !"]],
		["Veuve Carson", ["Les temps sont durs depuis la mine.", "Garde tes distances, jeune homme."]],
		["Palefrenier", ["Ton cheval est à l'écurie, prêt à filer.", "File vite, ils lanceront une battue."]],
		["Prêcheur", ["Repens-toi, pécheur !", "Que le Seigneur ait pitié de ton butin."]],
	]
	for i in range(names.size()):
		var nx: float = centers[mini(i * 2, centers.size() - 1)] + 40.0
		_add_npc(Vector2(nx, 1120.0 + (i % 3) * 80.0), Vector2(1, 0.2).rotated(i),
				Color(0.3 + 0.1 * (i % 3), 0.4, 0.4 + 0.1 * (i % 2)), Color(0.9, 0.8, 0.6),
				names[i][0], names[i][1])

	# Puits (collision) un peu à l'écart pour ne pas gêner la rue.
	_foots.append(Rect2(WELL - Vector2(40, 36), Vector2(80, 72)))

	# Chevaux attachés devant l'ÉCURIE.
	for k in range(3):
		var hp := Vector2(ecurie_x - 80.0 + k * 80.0, 1000.0)
		_horses.append(hp)
		_foots.append(Rect2(hp - Vector2(17, 12), Vector2(34, 24)))

	# Tumbleweeds qui roulent dans la rue (décor mobile, sans collision).
	for k in range(5):
		_tumble.append({
			"pos": Vector2(randf_range(FLOOR.position.x, FLOOR.end.x), randf_range(1150.0, 1420.0)),
			"vel": Vector2(randf_range(70.0, 150.0) * (1.0 if randf() < 0.7 else -1.0), randf_range(-12.0, 12.0)),
			"spin": 0.0})

	# Gardes postés DANS la banque (ripostent quand on force le coffre).
	_pmax = (5 if GameManager.assist else 3) + SaveManager.hp_bonus()
	_php = _pmax
	var bd = _bank_dict()
	if bd != null:
		var bf: Rect2 = bd["foot"]
		for gu in [0.30, 0.70]:
			_bank_guards.append({
				"pos": Vector2(bf.position.x + bf.size.x * gu, bf.position.y + bf.size.y * 0.30),
				"facing": Vector2.DOWN, "hp": 2, "alive": true, "fire_cd": randf_range(0.4, 1.2)})

	# Bandits qui rôdent dans la grand-rue : du gibier à dégommer pour du cash.
	for i in range(4):
		_bandits.append(_new_bandit(true))


## Crée un bandit (à un point de la rue, loin du joueur si demandé).
func _new_bandit(at_edge := false) -> Dictionary:
	var px := _rng.randf_range(FLOOR.position.x + 200.0, FLOOR.end.x - 200.0)
	if at_edge:
		px = FLOOR.position.x + 120.0 if _rng.randf() < 0.5 else FLOOR.end.x - 120.0
	var py := _rng.randf_range(1080.0, 1380.0)
	return {"pos": Vector2(px, py), "vel": Vector2.RIGHT.rotated(_rng.randf() * TAU) * BANDIT_SPEED,
			"hp": 2, "alive": true, "fire_cd": _rng.randf_range(1.0, 2.5), "wander_t": 0.0, "respawn": 0.0}


func _add_building(region: Rect2, pos: Vector2, h: float, label: String, tint: Color,
		flavor: String, foot: Vector2, enter := "") -> void:
	# Bâtiments AGRANDIS (on doit pouvoir marcher dedans confortablement).
	foot = foot * 1.35
	var foot_rect := Rect2(pos - Vector2(foot.x * 0.5, foot.y * 0.6), foot)
	# TOUT est ENTRABLE, sur le même plan (banque comprise).
	_buildings.append({"region": region, "pos": pos, "h": h, "label": label,
			"tint": tint, "flavor": flavor, "enter": enter, "foot": foot_rect, "enterable": true})
	# Tous les bâtiments bordent la grand-rue (en bas) et lui FONT FACE : la porte
	# (ouverture de collision) est sur le côté +y, côté rue = côté de la façade.
	_add_walls(foot_rect, 0)


## 4 murs de collision avec une ouverture (porte) centrée sur le côté `open`
## (0=+y, 1=-y, 2=+x, 3=-x). Le joueur entre par cette porte.
func _add_walls(r: Rect2, open: int) -> void:
	var t := 18.0
	var gap := 0.42                      # part centrale ouverte (porte)
	_h_wall(r, r.position.y, t, open == 1, gap)        # mur haut (-y)
	_h_wall(r, r.end.y - t, t, open == 0, gap)         # mur bas (+y)
	_v_wall(r, r.position.x, t, open == 3, gap)        # mur gauche (-x)
	_v_wall(r, r.end.x - t, t, open == 2, gap)         # mur droit (+x)


func _h_wall(r: Rect2, y: float, t: float, opened: bool, gap: float) -> void:
	if not opened:
		_foots.append(Rect2(Vector2(r.position.x, y), Vector2(r.size.x, t)))
	else:
		var s := r.size.x * (1.0 - gap) * 0.5
		_foots.append(Rect2(Vector2(r.position.x, y), Vector2(s, t)))
		_foots.append(Rect2(Vector2(r.end.x - s, y), Vector2(s, t)))


func _v_wall(r: Rect2, x: float, t: float, opened: bool, gap: float) -> void:
	if not opened:
		_foots.append(Rect2(Vector2(x, r.position.y), Vector2(t, r.size.y)))
	else:
		var s := r.size.y * (1.0 - gap) * 0.5
		_foots.append(Rect2(Vector2(x, r.position.y), Vector2(t, s)))
		_foots.append(Rect2(Vector2(x, r.end.y - s), Vector2(t, s)))


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
		_update_commerce_card()
		_update_bank_heist(delta)
		_update_bandits(delta)
		_update_boss(delta)
		_update_rush(delta)
		_update_raid(delta)
		_update_town_combat(delta)
		_update_floaters(delta)
		_update_streak(delta)
	_update_tumble(delta)
	for n in _npcs:
		NpcAI.update(n, delta, _blocked, _rng)
	# Chasseurs de primes (lot 14) : traque active si la prime est haute.
	if not _entered:
		if _wanted.update(delta, _player_pos, SaveManager.notoriety, FLOOR, _blocked):
			_on_caught_by_hunter()
		_update_wanted_label()
	# Occlusion : un bâtiment qui masque le joueur devient transparent (toit/murs).
	# Fondu lissé pour éviter le clignotement quand on entre/sort de sa silhouette.
	var occ := clampf(delta * 9.0, 0.0, 1.0)
	for b in _buildings:
		b["fade"] = lerpf(float(b.get("fade", 1.0)), _occlusion_target(b), occ)
	_update_coach(delta)
	# Rotation douce de la vue vers l'angle visé (pivote tout le décor).
	if absf(angle_difference(Iso.yaw, _yaw_target)) > 0.0005:
		Iso.yaw = lerp_angle(Iso.yaw, _yaw_target, clampf(delta * 9.0, 0.0, 1.0))
	_cam = _cam.lerp(_camera_target(), clampf(delta * 8.0, 0.0, 1.0))
	# Tremblement d'impact (kills) : décalage aléatoire qui s'amortit.
	var shake_off := Vector2.ZERO
	if _shake > 0.1:
		shake_off = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * _shake
	position = _cam + shake_off
	_hint_t += delta
	queue_redraw()


## Bandeau de prime : montant + nombre de chasseurs aux trousses.
func _update_wanted_label() -> void:
	if _wanted_label == null:
		return
	var noto: int = SaveManager.notoriety
	if not _wanted.active(noto):
		_wanted_label.text = ""
		return
	var n := _wanted.hunters.size()
	if n > 0:
		_wanted_label.text = "⚠ PRIME : %d $   ·   %d chasseur%s à tes trousses — FUIS !" % [
				_wanted.bounty(noto), n, "s" if n > 1 else ""]
	else:
		_wanted_label.text = "⚠ PRIME : %d $   ·   tu es RECHERCHÉ" % _wanted.bounty(noto)


## Un chasseur t'a rattrapé : il empoche une part de la prime, la chasse se calme.
func _on_caught_by_hunter() -> void:
	var noto: int = SaveManager.notoriety
	var take: int = mini(_wanted.bounty(noto), int(SaveManager.total_money * 0.4))
	SaveManager.spend(take)
	SaveManager.notoriety = maxi(0, noto - 3)   # la traque retombe
	_wanted.scatter(5.0)
	if _horse_ctrl.mounted:
		_dismount_horse()
	_show_toast("Chasseurs de primes ! Ils empochent %d $ et te laissent filer." % take)
	AudioManager.play("hit_player", -2.0)


## Couleur teintée par l'opacité du bâtiment courant (occlusion).
func _fa(c: Color) -> Color:
	return Color(c.r, c.g, c.b, c.a * _fade)


## Opacité cible d'un bâtiment : 1 normalement, ~0.3 quand il couvre le joueur
## à l'écran tout en étant dessiné par-dessus lui (donc en train de le masquer).
## Fonctionne à toutes les rotations (project/depth intègrent déjà le yaw).
func _occlusion_target(b: Dictionary) -> float:
	var fr: Rect2 = b["foot"]
	# ENTRABLE : le joueur est DEDANS -> toit/murs très transparents (on voit l'intérieur).
	if bool(b.get("enterable", false)) and fr.has_point(_player_pos):
		return 0.18
	# Dessiné AVANT le joueur (derrière lui) -> ne peut pas le masquer.
	if Iso.depth(b["pos"]) - 40.0 <= Iso.depth(_player_pos):
		return 1.0
	var ps := Iso.project(_player_pos)
	var corners := [Iso.project(fr.position), Iso.project(Vector2(fr.end.x, fr.position.y)),
			Iso.project(fr.end), Iso.project(Vector2(fr.position.x, fr.end.y))]
	var minx: float = corners[0].x
	var maxx: float = corners[0].x
	var miny: float = corners[0].y
	var maxy: float = corners[0].y
	for p in corners:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
		miny = minf(miny, p.y)
		maxy = maxf(maxy, p.y)
	var height := 250.0 if str(b["label"]) == "★ BANQUE ★" else 180.0
	var pad := 8.0
	if ps.x > minx - pad and ps.x < maxx + pad and ps.y > miny - height and ps.y < maxy + pad:
		return 0.3
	return 1.0


## Fait pivoter la vue par pas de 45° (la simulation reste inchangée).
func _rotate_view(steps: int) -> void:
	_yaw_target += float(steps) * PI / 4.0


## Choisit l'interaction la plus proche (banque, saloon, PNJ, commerce) et gère E.
func _update_interaction() -> void:
	_near_label = ""
	_target_kind = ""
	_target_npc = null
	_target_flavor = ""
	# À cheval : la seule interaction est de descendre (on lâche les autres).
	if _horse_ctrl.mounted:
		_can_enter = false
		_target_kind = "dismount"
		_near_label = "Descendre du cheval"
		_target_anchor = _player_pos
		var held_d := InputManager.is_interact_held()
		if held_d and not _interact_was:
			_do_action()
		_interact_was = held_d
		_update_action_button()
		return
	# On ENTRE dans la banque en marchant (porte ouverte) ; le braquage se lance
	# une fois DANS le hall, au coffre (E).
	# Dans le hall de la banque, près du coffre, pas encore forcé : prompt braquage.
	var bank = _bank_dict()
	_can_enter = false
	if bank != null and not _heist_done and not _vault_cracking \
			and (bank["foot"] as Rect2).has_point(_player_pos) \
			and _player_pos.distance_to(_vault_world(bank)) < 130.0:
		_can_enter = true
		_target_kind = "bank"
		_near_label = "FORCER LE COFFRE (E)"
		_target_anchor = _vault_world(bank)
	if _can_enter:
		pass
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
		# Commerces : SALOON s'entre (scène) ; les boutiques (gunsmith/pharmacy/store)
		# s'explorent au même plan -> pas de prompt E, la carte d'achat s'ouvre seule
		# quand on est dedans. Les bâtiments d'ambiance affichent leur texte.
		for b in _buildings:
			var en := str(b["enter"])
			if en in ["gunsmith", "pharmacy", "store"]:
				continue
			if b["flavor"] == "" and en == "":
				continue
			var d := _player_pos.distance_to(b["pos"] + Vector2(0, 60))
			if d < best:
				best = d
				_target_anchor = b["pos"] + Vector2(0, 60)
				if en != "":
					_target_kind = en   # "saloon"
					_near_label = "Entrer au %s" % b["label"]
				else:
					_target_kind = "flavor"
					_target_flavor = b["flavor"]
					_near_label = b["label"]
		# Chevaux : monter en selle.
		for hp in _horses:
			var d := _player_pos.distance_to(hp)
			if d < best:
				best = d
				_target_kind = "mount"
				_near_label = "Monter le cheval"
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
		"npc": _talk(_target_npc)
		"mount": _mount_nearest_horse()
		"dismount": _dismount_horse()
		"flavor": _show_toast(_target_flavor)


## Vrai si le joueur est dans le footprint de la banque (hall in-map).
func _inside_bank() -> bool:
	for b in _buildings:
		if str(b["label"]) == "★ BANQUE ★":
			return (b["foot"] as Rect2).has_point(_player_pos)
	return false


## Bâtiment-commerce dont le footprint contient le joueur (ou null).
func _building_inside() -> Variant:
	for b in _buildings:
		if str(b.get("enter", "")) in ["gunsmith", "pharmacy", "store"] \
				and (b["foot"] as Rect2).has_point(_player_pos):
			return b
	return null


## Carte d'achat NON-MODALE : s'ouvre seule quand on entre dans un commerce,
## se ferme quand on en sort. La ville reste visible (pas de fond noir, pas de
## changement de scène) -> rue et intérieurs sur le même plan.
func _update_commerce_card() -> void:
	var inside = _building_inside()
	var cat := ""
	if inside != null:
		cat = str(inside["enter"])
	if cat == "":
		if _shop_layer != null:
			_close_commerce()
		return
	if _shop_layer == null or _shop_cat != cat:
		_shop_cat = cat
		_build_commerce_card()


func _close_commerce() -> void:
	_shopping = false
	_shop_cat = ""
	if _shop_layer != null:
		_shop_layer.queue_free()
		_shop_layer = null


func _build_commerce_card() -> void:
	if _shop_layer != null:
		_shop_layer.queue_free()
	_shopping = true
	_shop_layer = CanvasLayer.new()
	_shop_layer.layer = 4
	add_child(_shop_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # NON-MODAL : la ville reste cliquable
	root.theme = UiTheme.build()
	_shop_layer.add_child(root)
	# Petite carte ancrée à droite (la ville reste visible derrière).
	var panel := UiTheme.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.position = Vector2(-372, 0)
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(330, 0)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var titles := {"gunsmith": "🔫 ARMURIER", "pharmacy": "➕ CABINET DU DOC", "store": "🛒 MAGASIN GÉNÉRAL"}
	box.add_child(UiTheme.title(str(titles.get(_shop_cat, "BOUTIQUE")), 24))
	_shop_money = UiTheme.title("Magot : %d $" % SaveManager.total_money, 16, Color(0.9, 0.9, 0.6))
	box.add_child(_shop_money)
	_shop_rows = VBoxContainer.new()
	_shop_rows.add_theme_constant_override("separation", 6)
	box.add_child(_shop_rows)
	_fill_commerce_rows()
	var hint := UiTheme.title("Éloigne-toi pour ressortir", 13, Color(0.78, 0.74, 0.6))
	box.add_child(hint)
	AudioManager.play("click")


func _fill_commerce_rows() -> void:
	for c in _shop_rows.get_children():
		c.queue_free()
	_shop_money.text = "Magot : %d $" % SaveManager.total_money
	for key in SaveManager.UPGRADE_ORDER:
		if str(SaveManager.UPGRADE_DEFS[key].get("store", "")) != _shop_cat:
			continue
		_shop_rows.add_child(_commerce_row(key))


func _commerce_row(key: String) -> Control:
	var def: Dictionary = SaveManager.UPGRADE_DEFS[key]
	var lvl := SaveManager.get_level(key)
	var maxl := SaveManager.max_level(key)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.09, 0.06, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.5, 0.8, 0.4) if SaveManager.can_buy(key) else Color(0.5, 0.38, 0.22)
	sb.set_content_margin_all(9)
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var dots := ""
	for i in range(maxl):
		dots += "●" if i < lvl else "○"
	info.add_child(_ui_lbl("%s  %s" % [str(def["name"]), dots], 16, Color(1, 1, 1)))
	var desc := _ui_lbl(str(def["desc"]), 12, Color(0.82, 0.78, 0.68))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(150, 0)
	info.add_child(desc)
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(96, 48)
	var cost := SaveManager.next_cost(key)
	if cost < 0:
		buy.text = "MAX"
		buy.disabled = true
	else:
		buy.text = "Acheter\n%d $" % cost
		buy.disabled = not SaveManager.can_buy(key)
		buy.pressed.connect(func() -> void:
			if SaveManager.buy(key):
				AudioManager.play("pickup")
			_fill_commerce_rows())
	row.add_child(buy)
	return panel


func _ui_lbl(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Monte sur le cheval attaché le plus proche (il quitte le râtelier).
func _mount_nearest_horse() -> void:
	var best := 1.0e20
	var idx := -1
	for i in range(_horses.size()):
		var d := _player_pos.distance_to(_horses[i])
		if d < best:
			best = d
			idx = i
	if idx < 0:
		return
	_horses.remove_at(idx)
	_horse_ctrl.mount()
	_show_toast("En selle ! (E pour descendre)")


## Descend : le cheval reste là où on saute, de nouveau attachable.
func _dismount_horse() -> void:
	var rest := _horse_ctrl.dismount(_player_pos)
	_horses.append(rest)


## Icône d'action (emoji) selon le type de cible.
func _action_icon() -> String:
	match _target_kind:
		"bank", "saloon": return "🚪"
		"store", "shop": return "🛒"
		"gunsmith": return "🔫"
		"pharmacy": return "➕"
		"npc": return "💬"
		"mount", "dismount": return "🐴"
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


## Le braquage est désormais IN-MAP (pas de scène) : forcer le coffre démarre le
## crochetage automatique dans le hall.
func _enter_bank() -> void:
	if _heist_done or _vault_cracking:
		return
	_vault_cracking = true
	_alarm_on = true                 # l'alarme sonne : les gardes ripostent
	AudioManager.play("safe")
	_show_toast("⚠ ALARME ! Force le coffre et TIRE/FUIS !")


## Position MONDE du coffre (fond-centre du footprint de la banque).
func _vault_world(b: Dictionary) -> Vector2:
	var fr: Rect2 = b["foot"]
	return Vector2(fr.position.x + fr.size.x * 0.5, fr.position.y + fr.size.y * 0.18)


func _bank_dict() -> Variant:
	for b in _buildings:
		if str(b["label"]) == "★ BANQUE ★":
			return b
	return null


## Boucle du braquage in-map : crochetage du coffre SOUS LE FEU des gardes,
## tir du joueur, balles, dégâts. Pas de poursuite-piège : les gardes restent
## dans le hall, on file par la rue.
func _update_bank_heist(delta: float) -> void:
	var bank = _bank_dict()
	if bank == null:
		return
	var in_bank: bool = (bank["foot"] as Rect2).has_point(_player_pos)
	if _vault_cracking and not _heist_done:
		if _player_pos.distance_to(_vault_world(bank)) < 140.0:
			_vault_prog = minf(1.0, _vault_prog + delta / (3.0 * SaveManager.safe_mult()))
			if _vault_prog >= 1.0:
				_crack_vault(bank)
	# Combat des GARDES (uniquement si l'alarme a sonné).
	if _alarm_on:
		for g in _bank_guards:
			if not g["alive"]:
				continue
			g["fire_cd"] = float(g["fire_cd"]) - delta
			var to: Vector2 = _player_pos - (g["pos"] as Vector2)
			g["facing"] = to.normalized()
			if in_bank and float(g["fire_cd"]) <= 0.0 and to.length() < 460.0:
				_town_bullets.append({"pos": g["pos"], "vel": to.normalized() * 620.0, "friendly": false, "life": 1.0})
				g["fire_cd"] = (2.0 if GameManager.assist else 1.4)
		# L'alarme se calme : tous les gardes au sol, OU coffre fait + loin de la banque.
		var calm := not _any_guard_alive() and _town_bullets.is_empty()
		calm = calm or (_heist_done and _player_pos.distance_to(_bank_center) > 750.0)
		if calm:
			_alarm_on = false
	# PV affiché pendant l'alerte.
	if _hp_label != null:
		if _alarm_on:
			var s := "PV  "
			for i in range(_pmax):
				s += "♥" if i < _php else "♡"
			_hp_label.text = s
		elif _hp_label.text != "":
			_hp_label.text = ""


## Combat ville : AUTO-VISÉE + TIR CONTINU sur l'ennemi le plus proche (mains
## libres, mobile-friendly). Le clic/espace force le tir vers la souris.
func _update_town_combat(delta: float) -> void:
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_php_dmg_cd = maxf(0.0, _php_dmg_cd - delta)
	_muzzle_t = maxf(0.0, _muzzle_t - delta)
	# Cible auto = hostile le plus proche dans le rayon.
	_has_target = false
	var best := AUTO_RANGE * SaveManager.aim_range_mult()
	for h in _hostiles():
		var d := _player_pos.distance_to(h)
		if d < best:
			best = d
			_aim_target = h
			_has_target = true
	var can_shoot := not _horse_ctrl.mounted and not _shopping
	var manual := InputManager.is_fire_pressed()
	if can_shoot and _fire_cd <= 0.0 and (manual or _has_target):
		var aim: Vector2
		if manual:
			aim = _aim_world() - _player_pos          # clic = visée souris
		elif _has_target:
			aim = _aim_target - _player_pos           # auto = ennemi le plus proche
		if aim.length() < 1.0:
			aim = _facing
		aim = aim.normalized()
		_facing = aim
		_town_bullets.append({"pos": _player_pos + aim * 18.0, "vel": aim * 860.0, "friendly": true, "life": 1.1})
		_fire_cd = 0.22 * SaveManager.firerate_mult()   # tir rapide et continu
		_muzzle_t = 0.06
		AudioManager.play("click")
	if not _town_bullets.is_empty():
		_advance_town_bullets(delta)


## Tous les ennemis ciblables (bandits, chasseurs de primes, gardes, posse).
func _hostiles() -> Array:
	var out: Array = []
	for b in _bandits:
		if b["alive"]:
			out.append(b["pos"])
	for hu in _wanted.hunters:
		out.append(hu["pos"])
	for g in _bank_guards:
		if g["alive"] and _alarm_on:
			out.append(g["pos"])
	for p in _posse:
		out.append(p["pos"])
	if _boss != null and _boss["alive"]:
		out.append(_boss["pos"])
	return out


## Mini-boss « RECHERCHÉ » : un hors-la-loi nommé, coriace, grosse prime.
## Apparaît périodiquement, fonce sur le joueur et lâche des rafales.
func _update_boss(delta: float) -> void:
	if _boss == null:
		_boss_timer = maxf(0.0, _boss_timer - delta)
		if _boss_timer <= 0.0 and not _horse_ctrl.mounted:
			_spawn_boss()
		return
	if not _boss["alive"]:
		return
	var to_p: Vector2 = _player_pos - (_boss["pos"] as Vector2)
	var want := to_p.normalized() * BOSS_SPEED
	# Garde ses distances : fonce s'il est loin, tourne autour s'il est proche.
	if to_p.length() < 220.0:
		var perp := Vector2(-want.y, want.x)
		want = (want * 0.2 + perp).normalized() * BOSS_SPEED
	_boss["vel"] = (_boss["vel"] as Vector2).lerp(want, clampf(delta * 2.0, 0.0, 1.0))
	_boss["pos"] = _try_move(_boss["pos"], (_boss["vel"] as Vector2).normalized(), BOSS_SPEED * delta, _blocked)
	_boss["fire_cd"] = float(_boss["fire_cd"]) - delta
	if to_p.length() < 460.0 and float(_boss["fire_cd"]) <= 0.0:
		# Rafale de 3 balles en éventail.
		var base := to_p.normalized()
		for a in [-0.16, 0.0, 0.16]:
			var dir := base.rotated(a)
			_town_bullets.append({"pos": _boss["pos"] + dir * 22.0, "vel": dir * 560.0, "friendly": false, "life": 1.1})
		_boss["fire_cd"] = _rng.randf_range(1.6, 2.4)
		AudioManager.play("shot", -8.0)


func _spawn_boss() -> void:
	var hp := 11 + SaveManager.notoriety
	var px := FLOOR.position.x + 120.0 if _rng.randf() < 0.5 else FLOOR.end.x - 120.0
	var py := _rng.randf_range(1080.0, 1380.0)
	_boss = {"pos": Vector2(px, py), "vel": Vector2.ZERO, "hp": hp, "max_hp": hp, "alive": true,
		"fire_cd": 1.2, "name": BOSS_NAMES[_rng.randi() % BOSS_NAMES.size()],
		"bounty": int(round((650 + SaveManager.notoriety * 130) * SaveManager.bounty_mult()))}
	_floaters.append({"pos": Vector2(px, py - 30), "t": 0.0, "text": "RECHERCHÉ !", "col": Color(1, 0.3, 0.25)})
	AudioManager.play("alarm", -6.0)


## Le boss est abattu : grosse prime, juice marqué, prochain délai relancé.
func _kill_boss() -> void:
	var bounty: int = int(_boss["bounty"])
	SaveManager.refund(bounty)
	_shake = maxf(_shake, 12.0)
	for i in range(20):
		_bursts.append({"pos": _boss["pos"], "vel": Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(70, 260),
			"t": 0.0, "col": Color(0.8, 0.1, 0.08) if i % 2 == 0 else Color(0.95, 0.8, 0.3)})
	_floaters.append({"pos": _boss["pos"], "t": 0.0, "text": "%s ABATTU  +%d $" % [_boss["name"], bounty], "col": Color(1, 0.9, 0.4)})
	AudioManager.play("win", -2.0)
	_boss = null
	_boss_timer = _rng.randf_range(28.0, 40.0)


## RUÉE : vague de bandits qui déferle, primes ×2 le temps de l'événement.
func _update_rush(delta: float) -> void:
	if _rush_active:
		_rush_t = maxf(0.0, _rush_t - delta)
		if _rush_t <= 0.0:
			_rush_active = false
			_rush_cd = _rng.randf_range(36.0, 52.0)
	else:
		_rush_cd = maxf(0.0, _rush_cd - delta)
		if _rush_cd <= 0.0 and not _horse_ctrl.mounted:
			_start_rush()


func _start_rush() -> void:
	_rush_active = true
	_rush_t = RUSH_DURATION
	for i in range(5):
		var b := _new_bandit(true)
		b["rush"] = true
		_bandits.append(b)
	_shake = maxf(_shake, 6.0)
	_floaters.append({"pos": _player_pos + Vector2(0, -40), "t": 0.0, "text": "RUÉE !", "col": Color(1, 0.5, 0.2)})
	AudioManager.play("alarm", -4.0)


## DESCENTE DE LA LOI : à haute notoriété, une escouade de lois prend la ville
## d'assaut. Les nettoyer FAIT RETOMBER la notoriété (gestion du « chaud » au flingue).
func _update_raid(delta: float) -> void:
	if _raid_active:
		if _raid_left <= 0:
			_raid_active = false
			_raid_cd = _rng.randf_range(40.0, 60.0)
			SaveManager.lose_notoriety()
			_shake = maxf(_shake, 8.0)
			_floaters.append({"pos": _player_pos + Vector2(0, -46), "t": 0.0, "text": "LOI REPOUSSÉE — notoriété ↓", "col": Color(0.6, 1.0, 0.7)})
		return
	if SaveManager.notoriety < RAID_MIN_NOTORIETY:
		return
	_raid_cd = maxf(0.0, _raid_cd - delta)
	if _raid_cd <= 0.0 and not _horse_ctrl.mounted:
		_start_raid()


func _start_raid() -> void:
	_raid_active = true
	var n := 4 + clampi(SaveManager.notoriety / 2, 0, 4)
	_raid_left = n
	for i in range(n):
		var b := _new_bandit(true)
		b["law"] = true
		b["hp"] = 3                       # lois plus coriaces
		b["respawn"] = 999999.0           # ne réapparaissent jamais
		_bandits.append(b)
	_shake = maxf(_shake, 6.0)
	_floaters.append({"pos": _player_pos + Vector2(0, -40), "t": 0.0, "text": "DESCENTE DE LA LOI !", "col": Color(0.5, 0.7, 1.0)})
	AudioManager.play("alarm", -3.0)


## Bandits : rôdent, tirent parfois sur le joueur ; respawn après mort.
func _update_bandits(delta: float) -> void:
	var drop: Array = []
	for b in _bandits:
		if not b["alive"]:
			# Les bandits de RUÉE ne réapparaissent pas une fois la vague finie ;
			# les LOIS d'une descente ne réapparaissent jamais.
			if (b.get("rush", false) and not _rush_active) or b.get("law", false):
				drop.append(b)
				continue
			b["respawn"] = float(b["respawn"]) - delta
			if float(b["respawn"]) <= 0.0:
				var nb := _new_bandit(true)
				for k in nb:
					b[k] = nb[k]
			continue
		# Errance : change de cap de temps en temps.
		b["wander_t"] = float(b["wander_t"]) - delta
		if float(b["wander_t"]) <= 0.0:
			b["wander_t"] = _rng.randf_range(0.8, 2.0)
			b["vel"] = Vector2.RIGHT.rotated(_rng.randf() * TAU) * BANDIT_SPEED
		# S'approche un peu du joueur s'il est proche (sinon errance).
		var to_p: Vector2 = _player_pos - (b["pos"] as Vector2)
		if to_p.length() < 360.0:
			b["vel"] = (b["vel"] as Vector2).lerp(to_p.normalized() * BANDIT_SPEED, 0.04)
		b["pos"] = _try_move(b["pos"], (b["vel"] as Vector2).normalized(), BANDIT_SPEED * delta, _blocked)
		# Riposte.
		b["fire_cd"] = float(b["fire_cd"]) - delta
		if to_p.length() < 340.0 and float(b["fire_cd"]) <= 0.0:
			_town_bullets.append({"pos": b["pos"], "vel": to_p.normalized() * 560.0, "friendly": false, "life": 1.0})
			b["fire_cd"] = _rng.randf_range(1.6, 2.8)
	for b in drop:
		_bandits.erase(b)


## Série de kills (combo) + éclats de mort + amortissement du tremblement.
func _update_streak(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 26.0)
	if _streak_t > 0.0:
		_streak_t = maxf(0.0, _streak_t - delta)
		if _streak_t == 0.0:
			_streak = 0
	var live: Array[Dictionary] = []
	for p in _bursts:
		p["t"] = float(p["t"]) + delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		p["vel"] = (p["vel"] as Vector2) * 0.90
		if float(p["t"]) < 0.6:
			live.append(p)
	_bursts = live


## Récompense un kill : avance la série, donne la prime majorée, juice d'impact.
func _reward_kill(at: Vector2) -> void:
	_streak += 1
	_streak_t = STREAK_WINDOW
	var mult := 1.0 + 0.5 * float(_streak - 1)          # x1, x1.5, x2, x2.5...
	if _rush_active:
		mult *= 2.0                                     # RUÉE : primes doublées
	var bounty := int(round((120 + SaveManager.notoriety * 20) * mult * SaveManager.bounty_mult()))
	SaveManager.refund(bounty)
	_shake = maxf(_shake, 7.0)
	AudioManager.play("hit_guard")
	var col := Color(1, 0.9, 0.4) if _streak < 2 else Color(1, 0.6, 0.2)
	var txt := "+%d $" % bounty
	if _streak >= 2:
		txt = "x%d  +%d $" % [_streak, bounty]
	_floaters.append({"pos": at, "t": 0.0, "text": txt, "col": col})
	for i in range(10):
		_bursts.append({"pos": at, "vel": Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(60, 200),
				"t": 0.0, "col": Color(0.8, 0.1, 0.08) if i % 2 == 0 else Color(0.5, 0.35, 0.2)})


## Pop-ups flottants (+$, "TOUCHÉ"...).
func _update_floaters(delta: float) -> void:
	var live: Array[Dictionary] = []
	for f in _floaters:
		f["t"] = float(f["t"]) + delta
		f["pos"] = (f["pos"] as Vector2) + Vector2(0, -26.0 * delta)
		if float(f["t"]) < 1.1:
			live.append(f)
	_floaters = live


## Tumbleweeds : roulent au gré du vent, rebondissent doucement, bouclent aux bords.
func _update_tumble(delta: float) -> void:
	for w in _tumble:
		var p: Vector2 = w["pos"]
		p += (w["vel"] as Vector2) * delta
		w["spin"] = float(w["spin"]) + (w["vel"] as Vector2).x * delta * 0.05
		if p.x < FLOOR.position.x - 60.0:
			p.x = FLOOR.end.x + 40.0
			p.y = randf_range(1150.0, 1420.0)
		elif p.x > FLOOR.end.x + 60.0:
			p.x = FLOOR.position.x - 40.0
			p.y = randf_range(1150.0, 1420.0)
		w["pos"] = p


func _aim_world() -> Vector2:
	# Souris -> monde (la ville est en iso ; le noeud porte caméra+zoom).
	return Iso.unproject(get_local_mouse_position())


func _any_guard_alive() -> bool:
	for g in _bank_guards:
		if g["alive"]:
			return true
	return false


func _advance_town_bullets(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for b in _town_bullets:
		b["pos"] += (b["vel"] as Vector2) * delta
		b["life"] = float(b["life"]) - delta
		if float(b["life"]) <= 0.0:
			continue
		var hit := false
		if b["friendly"]:
			# Mini-boss recherché : encaisse plusieurs balles, grosse prime.
			if _boss != null and _boss["alive"] and (_boss["pos"] as Vector2).distance_to(b["pos"]) < 26.0:
				_boss["hp"] = int(_boss["hp"]) - 1
				hit = true
				_bursts.append({"pos": b["pos"], "vel": Vector2.RIGHT.rotated(_rng.randf() * TAU) * 110.0,
					"t": 0.0, "col": Color(0.8, 0.2, 0.15)})
				_shake = maxf(_shake, 3.0)
				if int(_boss["hp"]) <= 0:
					_boss["alive"] = false
					_kill_boss()
			# Bandits d'abord (gibier principal).
			if not hit:
				for bd in _bandits:
					if bd["alive"] and (bd["pos"] as Vector2).distance_to(b["pos"]) < 22.0:
						bd["hp"] = int(bd["hp"]) - 1
						hit = true
						if int(bd["hp"]) <= 0:
							bd["alive"] = false
							bd["respawn"] = randf_range(6.0, 10.0)
							if bd.get("law", false):
								_raid_left -= 1   # un de moins dans la descente
							_reward_kill(bd["pos"])
						break
			if not hit:
				for g in _bank_guards:
					if g["alive"] and (g["pos"] as Vector2).distance_to(b["pos"]) < 22.0:
						g["hp"] = int(g["hp"]) - 1
						hit = true
						if int(g["hp"]) <= 0:
							g["alive"] = false
						break
			# Chasseurs de primes : une balle bien placée les met en fuite.
			if not hit:
				for hu in _wanted.hunters:
					if (hu["pos"] as Vector2).distance_to(b["pos"]) < 22.0:
						_wanted.hunters.erase(hu)
						_wanted.grace = 3.0
						hit = true
						break
			# Posse (lois lancées après un braquage).
			if not hit:
				for p in _posse:
					if (p["pos"] as Vector2).distance_to(b["pos"]) < 22.0:
						_posse.erase(p)
						hit = true
						break
		else:
			if _php_dmg_cd <= 0.0 and _player_pos.distance_to(b["pos"]) < 20.0:
				_hurt_player()
				hit = true
		if not hit:
			alive.append(b)
	_town_bullets = alive


func _hurt_player() -> void:
	_php = maxi(0, _php - 1)
	_php_dmg_cd = 0.8 if GameManager.assist else 0.5
	AudioManager.play("hit_player")
	if _php <= 0:
		_busted()


## Avance vers une direction en contournant les obstacles (poursuite de la loi).
func _try_move(pos: Vector2, dir: Vector2, dist: float, blocked: Callable) -> Vector2:
	for ang in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var np: Vector2 = pos + dir.rotated(ang) * dist
		if not blocked.call(np):
			return np
	return pos


func _crack_vault(bank: Dictionary) -> void:
	_heist_done = true
	_vault_cracking = false
	var tier: int = int(GameManager.current_town_def().get("level", 1))
	var reward := 700 + tier * 500 + _rng.randi_range(0, 200)
	GameManager.bank_robbed_in_town(reward)
	_show_toast("COFFRE FORCÉ ! +%d $ — FILE par la rue avant qu'ils ne t'aient !" % reward)
	AudioManager.play("safe")
	# Les gardes survivants continuent de tirer tant que tu es dans le hall ; sors
	# par la rue pour échapper au feu (la notoriété monte -> chasseurs ensuite).


## Pris/abattu pendant le braquage -> prison (caution ou évasion).
func _busted() -> void:
	if _entered:
		return
	_entered = true   # gèle la ville
	_show_toast("Abattu pendant le braquage !")
	AudioManager.play("lose", 2.0)
	AudioManager.stop_music()
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(func() -> void: GameManager.go_to_jail())


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
	Iso.top_down = false   # la ville se dessine en iso
	_draw_ground()
	_draw_well()
	_draw_hitch()
	# Repère banque : halo doré + flèche flottante (devant la grosse banque).
	var d := Iso.project(_bank_center + Vector2(0, 170.0))
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
	for h in _wanted.hunters:
		items.append({"d": Iso.depth(h["pos"]), "k": "hunter", "o": h})
	for p in _posse:
		items.append({"d": Iso.depth(p["pos"]), "k": "law", "o": p})
	for g in _bank_guards:
		if g["alive"]:
			items.append({"d": Iso.depth(g["pos"]), "k": "bankguard", "o": g})
	for w in _tumble:
		items.append({"d": Iso.depth(w["pos"]), "k": "tumble", "o": w})
	for bd in _bandits:
		if bd["alive"]:
			items.append({"d": Iso.depth(bd["pos"]), "k": "bandit", "o": bd})
	if _boss != null and _boss["alive"]:
		items.append({"d": Iso.depth(_boss["pos"]), "k": "boss", "o": _boss})
	items.append({"d": Iso.depth(_player_pos), "k": "me", "o": null})
	items.sort_custom(func(a, b): return a["d"] < b["d"])
	for it in items:
		match it["k"]:
			"b":
				_fade = float(it["o"].get("fade", 1.0))
				_draw_building(it["o"])
				_fade = 1.0
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
			"hunter": _draw_hunter(it["o"])
			"law": _draw_lawman(it["o"])
			"bankguard": _draw_bank_guard(it["o"])
			"bandit": _draw_bandit(it["o"])
			"boss": _draw_boss(it["o"])
			"tumble": _draw_tumble(it["o"])
			"me": _draw_me()
	# Barre de crochetage du coffre, au-dessus de la banque.
	_draw_vault_progress()
	# Balles du braquage (traceurs).
	for b in _town_bullets:
		var bp: Vector2 = Iso.project(b["pos"])
		var bdir: Vector2 = (b["vel"] as Vector2).normalized()
		var bcol := Color(1, 0.9, 0.4) if b["friendly"] else Color(1, 0.45, 0.2)
		draw_line(bp - bdir * 12.0, bp, Color(bcol.r, bcol.g, bcol.b, 0.5), 3.0)
		draw_circle(bp, 3.0, bcol)

	# Éclats de mort (sang/poussière) projetés à l'impact.
	for p in _bursts:
		var pp := Iso.project(p["pos"])
		var pa: float = clampf(1.0 - float(p["t"]) / 0.6, 0.0, 1.0)
		var pc: Color = p["col"]
		draw_circle(pp, 2.0 + pa * 2.0, Color(pc.r, pc.g, pc.b, pa))

	# Réticule de visée auto sur l'ennemi ciblé.
	if _has_target:
		var rp := Iso.project(_aim_target) + Vector2(0, -18)
		var pulse := 9.0 + sin(_hint_t * 8.0) * 2.0
		draw_arc(rp, pulse, 0, TAU, 20, Color(1.0, 0.3, 0.25, 0.9), 2.0)
		for a in range(4):
			var dirr := Vector2.RIGHT.rotated(TAU * a / 4.0)
			draw_line(rp + dirr * (pulse - 3.0), rp + dirr * (pulse + 4.0), Color(1.0, 0.3, 0.25), 2.0)

	# Pop-ups flottants (+$ / coups).
	for f in _floaters:
		var fp := Iso.project(f["pos"]) + Vector2(0, -40)
		var fa: float = clampf(1.0 - float(f["t"]) / 1.1, 0.0, 1.0)
		var fc: Color = f["col"]
		_text(fp, str(f["text"]), 16, Color(fc.r, fc.g, fc.b, fa))

	# Bandeau de série (combo) — fixe à l'écran, monte en intensité.
	if _streak >= 2:
		var vp := get_viewport_rect().size
		var center := Vector2(vp.x * 0.5, 70.0) - position    # écran -> local
		var grow := 1.0 + clampf(_streak_t / STREAK_WINDOW, 0.0, 1.0) * 0.25
		var hot := clampf(float(_streak - 2) / 6.0, 0.0, 1.0)
		var bcol := Color(1.0, 0.85 - hot * 0.5, 0.3 - hot * 0.2)
		_text(center + Vector2(0, 6), "SÉRIE x%d" % _streak, int(26 * grow), bcol)
		# Jauge de temps restant avant rupture de la série.
		var gw := 150.0 * (_streak_t / STREAK_WINDOW)
		draw_rect(Rect2(center + Vector2(-75, 22), Vector2(150, 4)), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(center + Vector2(-75, 22), Vector2(gw, 4)), bcol)

	# Bandeau « RUÉE » : vague de bandits, primes ×2, jauge de temps restant.
	if _rush_active:
		var vpr := get_viewport_rect().size
		var cr := Vector2(vpr.x * 0.5, 40.0) - position
		var rp := 0.5 + 0.5 * sin(_hint_t * 6.0)
		_text(cr, "RUÉE ! primes ×2", int(24 + rp * 3.0), Color(1.0, 0.55 + 0.25 * rp, 0.2))
		var gw := 180.0 * (_rush_t / RUSH_DURATION)
		draw_rect(Rect2(cr + Vector2(-90, 18), Vector2(180, 5)), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(cr + Vector2(-90, 18), Vector2(gw, 5)), Color(1.0, 0.55, 0.2))

	# Bandeau « DESCENTE DE LA LOI » : escouade à repousser, notoriété ↓ à la clé.
	if _raid_active:
		var vpl := get_viewport_rect().size
		var cl := Vector2(vpl.x * 0.5, 78.0) - position
		var lp := 0.5 + 0.5 * sin(_hint_t * 5.0)
		_text(cl, "✦ DESCENTE DE LA LOI ✦", 22, Color(0.55 + 0.3 * lp, 0.75, 1.0))
		_text(cl + Vector2(0, 22), "Lois debout : %d  —  les abattre fait retomber ta prime" % _raid_left, 15, Color(0.8, 0.9, 1.0))

	# Bandeau « RECHERCHÉ » quand le mini-boss est en ville (fixe à l'écran).
	if _boss != null and _boss["alive"]:
		var vpb := get_viewport_rect().size
		var c := Vector2(vpb.x * 0.5, 116.0) - position
		var pulse := 0.5 + 0.5 * sin(_hint_t * 4.0)
		_text(c, "★ RECHERCHÉ ★", 22, Color(1.0, 0.3 + 0.3 * pulse, 0.2))
		_text(c + Vector2(0, 24), "%s — %d $" % [str(_boss["name"]), int(_boss["bounty"])], 16, Color(1, 0.85, 0.55))
		# Flèche indiquant la direction du boss.
		var dir := (Iso.project(_boss["pos"]) - (Vector2(vpb.x * 0.5, vpb.y * 0.5) - position)).normalized()
		draw_line(c + Vector2(0, 44), c + Vector2(0, 44) + dir * 26.0, Color(1, 0.4, 0.3), 3.0)

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
	# Hall in-map : visible à mesure que le toit devient transparent (on entre).
	if _fade < 0.92:
		_draw_interior(b, 1.0 - _fade)
	# Occlusion : couleurs sources teintées par _fade (transparence du toit/murs).
	var stone := _fa(Color(0.82, 0.74, 0.57))
	var side := stone.darkened(0.24)
	var roof := stone.darkened(0.34)
	var trim := _fa(Color(0.54, 0.43, 0.29))
	var gold := _fa(Color(0.95, 0.80, 0.34))
	var door := _fa(Color(0.24, 0.14, 0.08))
	var glass := _fa(Color(0.58, 0.73, 0.80))
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
## Intérieur visible in-map (sol bois + comptoir + tenancier + accents métier).
## `vis` = 0..1 : visibilité (1 = on est dedans, toit transparent).
func _draw_interior(b: Dictionary, vis: float) -> void:
	var fr: Rect2 = b["foot"]
	var U := Vector2(0, -1)
	var b0 := Iso.project(fr.position)
	var b1 := Iso.project(Vector2(fr.end.x, fr.position.y))
	var b2 := Iso.project(fr.end)
	var b3 := Iso.project(Vector2(fr.position.x, fr.end.y))
	var label := str(b["label"])
	# BANQUE : hall en marbre + comptoir de caisse + grande porte de coffre au fond.
	if label == "★ BANQUE ★":
		_draw_bank_interior(fr, b0, b1, b2, b3, vis)
		return
	# Sol en planches (autres bâtiments).
	draw_colored_polygon(PackedVector2Array([b0, b1, b2, b3]), _va(Color(0.52, 0.37, 0.22), vis))
	for k in range(1, 6):
		var t := float(k) / 6.0
		draw_line(b0.lerp(b1, t), b3.lerp(b2, t), _va(Color(0.40, 0.28, 0.16), vis * 0.8), 1.0)
	var enter := str(b.get("enter", ""))
	var service := label in ["FORGE", "DOCTEUR", "MAGASIN", "SALOON", "HÔTEL", "POSTE"]
	# Comptoir (service uniquement) : face avant + dessus.
	if service:
		var fl := b0.lerp(b3, 0.46)
		var fri := b1.lerp(b2, 0.46)
		var bl := b0.lerp(b3, 0.32)
		var br := b1.lerp(b2, 0.32)
		var ch := 16.0
		draw_colored_polygon(PackedVector2Array([fl, fri, fri + U * ch, fl + U * ch]), _va(Color(0.34, 0.22, 0.12), vis))
		draw_colored_polygon(PackedVector2Array([fl + U * ch, fri + U * ch, br + U * ch, bl + U * ch]),
				_va(Color(0.55, 0.40, 0.24), vis))
		draw_line(fl + U * ch, fri + U * ch, _va(Color(0.7, 0.55, 0.3), vis), 1.5)
	# Mobilier / accents selon le bâtiment.
	match label:
		"FORGE":
			for j in range(5):
				var p := b0.lerp(b1, 0.16 + j * 0.17) + U * 40.0
				draw_line(p, p + U * 22.0, _va(Color(0.3, 0.22, 0.14), vis), 3.0)   # râteliers de fusils
		"DOCTEUR":
			for j in range(5):
				var p := b0.lerp(b1, 0.16 + j * 0.17) + U * 40.0
				draw_circle(p, 4.0, _va([Color(0.5,0.8,0.5),Color(0.8,0.4,0.4),Color(0.5,0.6,0.9)][j % 3], vis))
		"SALOON":
			for uv in [Vector2(0.32, 0.72), Vector2(0.7, 0.74)]:
				var c := _bil(b0, b1, b2, b3, uv.x, uv.y)
				draw_colored_polygon(_ellipse(c, 14.0, 7.0), _va(Color(0.42, 0.28, 0.16), vis))   # tables rondes
				draw_circle(c + U * 4.0, 10.0, _va(Color(0.5, 0.34, 0.2), vis))
			for j in range(4):
				draw_circle(b0.lerp(b1, 0.2 + j * 0.18) + U * 44.0, 3.5, _va(Color(0.7, 0.6, 0.3), vis))  # bouteilles
		"ÉGLISE":
			for r in range(3):
				var v := 0.5 + r * 0.16
				draw_line(_bil(b0, b1, b2, b3, 0.2, v), _bil(b0, b1, b2, b3, 0.8, v), _va(Color(0.45, 0.32, 0.2), vis), 5.0)  # bancs
			var cr := _bil(b0, b1, b2, b3, 0.5, 0.12) + U * 36.0
			draw_line(cr, cr + U * 18.0, _va(Color(0.7, 0.6, 0.4), vis), 3.0)
			draw_line(cr + U * 12.0 + Vector2(-6, 0), cr + U * 12.0 + Vector2(6, 0), _va(Color(0.7, 0.6, 0.4), vis), 3.0)
		"SHÉRIF":
			var desk := _bil(b0, b1, b2, b3, 0.5, 0.4)
			draw_colored_polygon(PackedVector2Array([desk + Vector2(-22, 0), desk + Vector2(22, 0),
					desk + Vector2(22, 0) + U * 12.0, desk + Vector2(-22, 0) + U * 12.0]), _va(Color(0.36, 0.24, 0.14), vis))
			for j in range(4):  # barreaux de cellule à gauche
				var bx := _bil(b0, b1, b2, b3, 0.14, 0.35 + j * 0.14)
				draw_line(bx, bx + U * 30.0, _va(Color(0.5, 0.5, 0.55), vis), 2.5)
		"ÉCURIE":
			for uv in [Vector2(0.3, 0.6), Vector2(0.68, 0.66)]:
				var hay := _bil(b0, b1, b2, b3, uv.x, uv.y)
				draw_rect(Rect2(hay - Vector2(12, 10), Vector2(24, 14)), _va(Color(0.82, 0.7, 0.3), vis))   # bottes de foin
		_:
			for j in range(4):
				var p := b0.lerp(b1, 0.2 + j * 0.2) + U * 40.0
				draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), _va(Color(0.5, 0.36, 0.2), vis))   # caisses/étagères
	# Tenancier derrière le comptoir (commerces & lieux de service).
	if service and vis > 0.45:
		var keeper := Vector2(fr.get_center().x, fr.position.y + fr.size.y * 0.22)
		CharacterArt.draw_person(self, Iso.project(keeper), Vector2.DOWN, _keeper_palette(enter),
				false, false, 0.0, 0.0, 0.0)


## Point sur le sol du footprint en coordonnées (u = largeur, v = profondeur).
func _bil(b0: Vector2, b1: Vector2, b2: Vector2, b3: Vector2, u: float, v: float) -> Vector2:
	return b0.lerp(b1, u).lerp(b3.lerp(b2, u), v)


## Hall de banque riche (sol marbre + dallage, comptoir à guichets, gros coffre
## blindé au fond, colonnes, bureaux, piles d'or, lustre, caissier + garde).
func _draw_bank_interior(fr: Rect2, b0: Vector2, b1: Vector2, b2: Vector2, b3: Vector2, vis: float) -> void:
	var U := Vector2(0, -1)
	# Sol marbre + damier.
	draw_colored_polygon(PackedVector2Array([b0, b1, b2, b3]), _va(Color(0.80, 0.76, 0.68), vis))
	for ix in range(6):
		for iy in range(6):
			if (ix + iy) % 2 == 0:
				continue
			var p0 := _bil(b0, b1, b2, b3, ix / 6.0, iy / 6.0)
			var p1 := _bil(b0, b1, b2, b3, (ix + 1) / 6.0, iy / 6.0)
			var p2 := _bil(b0, b1, b2, b3, (ix + 1) / 6.0, (iy + 1) / 6.0)
			var p3 := _bil(b0, b1, b2, b3, ix / 6.0, (iy + 1) / 6.0)
			draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), _va(Color(0.70, 0.66, 0.58, 0.6), vis))
	# Tapis rouge central (de la porte au coffre).
	for v in range(7):
		var a := _bil(b0, b1, b2, b3, 0.42, v / 7.0)
		var bb := _bil(b0, b1, b2, b3, 0.58, v / 7.0)
		var c := _bil(b0, b1, b2, b3, 0.58, (v + 1) / 7.0)
		var dd := _bil(b0, b1, b2, b3, 0.42, (v + 1) / 7.0)
		draw_colored_polygon(PackedVector2Array([a, bb, c, dd]), _va(Color(0.55, 0.18, 0.16, 0.85), vis))
	# Colonnes (4) avec base et chapiteau.
	for cu in [0.14, 0.86]:
		for cv in [0.30, 0.62]:
			var cp := _bil(b0, b1, b2, b3, cu, cv)
			draw_colored_polygon(PackedVector2Array([cp + Vector2(-6, 0), cp + Vector2(6, 0),
					cp + Vector2(6, 0) + U * 46.0, cp + Vector2(-6, 0) + U * 46.0]), _va(Color(0.86, 0.82, 0.74), vis))
			draw_rect(Rect2(cp + Vector2(-9, -50), Vector2(18, 6)), _va(Color(0.7, 0.6, 0.35), vis))
			draw_rect(Rect2(cp + Vector2(-9, -4), Vector2(18, 6)), _va(Color(0.6, 0.55, 0.45), vis))
	# GROS coffre blindé au fond (porte ronde + boulons + volant).
	var vault := _bil(b0, b1, b2, b3, 0.5, 0.12) + U * 26.0
	draw_colored_polygon(PackedVector2Array([vault + Vector2(-46, 30), vault + Vector2(46, 30),
			vault + Vector2(46, -34), vault + Vector2(-46, -34)]), _va(Color(0.30, 0.31, 0.36), vis))   # cadre
	draw_circle(vault, 33.0, _va(Color(0.42, 0.43, 0.49), vis))
	draw_circle(vault, 33.0, _va(Color(0.86, 0.7, 0.3), vis), false, 4.0)
	for a in range(10):
		var ang := TAU * a / 10.0
		draw_circle(vault + Vector2.RIGHT.rotated(ang) * 27.0, 2.2, _va(Color(0.7, 0.72, 0.78), vis))   # boulons
	draw_circle(vault, 12.0, _va(Color(0.86, 0.72, 0.34), vis))
	for a in range(8):
		var ang2 := TAU * a / 8.0
		draw_line(vault, vault + Vector2.RIGHT.rotated(ang2) * 16.0, _va(Color(0.55, 0.42, 0.2), vis), 2.0)   # volant
	# Piles d'or et sacs de butin de part et d'autre du coffre.
	for su in [0.30, 0.70]:
		var gp := _bil(b0, b1, b2, b3, su, 0.20)
		for s in range(3):
			draw_circle(gp + U * (4.0 + s * 5.0), 7.0, _va(Color(0.95, 0.82, 0.32), vis))
			draw_arc(gp + U * (4.0 + s * 5.0), 7.0, 0, TAU, 12, _va(Color(0.7, 0.55, 0.2), vis), 1.0)
		var sk := _bil(b0, b1, b2, b3, su + 0.06, 0.30)
		draw_colored_polygon(_ellipse(sk + U * 6.0, 9.0, 11.0), _va(Color(0.78, 0.68, 0.5), vis))   # sac
		_text(sk + U * 12.0, "$", 12, _va(Color(0.5, 0.4, 0.2), vis))
	# Long COMPTOIR à guichets (avec grille/barreaux) en travers du hall.
	var cl := _bil(b0, b1, b2, b3, 0.10, 0.52)
	var cr := _bil(b0, b1, b2, b3, 0.90, 0.52)
	var ch := 18.0
	draw_colored_polygon(PackedVector2Array([cl, cr, cr + U * ch, cl + U * ch]), _va(Color(0.34, 0.22, 0.12), vis))   # façade
	draw_colored_polygon(PackedVector2Array([cl + U * ch, cr + U * ch,
			cr + U * ch + Vector2(0, -6), cl + U * ch + Vector2(0, -6)]), _va(Color(0.55, 0.40, 0.24), vis))   # plateau
	draw_line(cl + U * ch, cr + U * ch, _va(Color(0.75, 0.6, 0.32), vis), 1.5)
	for g in range(7):   # grilles de guichet
		var gx := cl.lerp(cr, 0.1 + g * 0.13)
		draw_line(gx + U * ch, gx + U * (ch + 26.0), _va(Color(0.55, 0.5, 0.35), vis), 1.5)
	draw_line(cl + U * (ch + 26.0), cr + U * (ch + 26.0), _va(Color(0.5, 0.45, 0.3), vis), 1.5)
	# Lustre central.
	var lust := _bil(b0, b1, b2, b3, 0.5, 0.42) + U * 70.0
	draw_circle(lust, 9.0, _va(Color(0.85, 0.7, 0.3, 0.7), vis))
	for a in range(6):
		draw_circle(lust + Vector2.RIGHT.rotated(TAU * a / 6.0) * 12.0, 2.5, _va(Color(1.0, 0.9, 0.5), vis))
	# Caissier derrière le comptoir (les 2 gardes sont des entités, dessinées via
	# le tri de profondeur : ils ripostent pendant le braquage).
	if vis > 0.45:
		var teller := Vector2(fr.get_center().x, fr.position.y + fr.size.y * 0.42)
		CharacterArt.draw_person(self, Iso.project(teller), Vector2.DOWN, _keeper_palette("bank"),
				false, false, 0.0, 0.0, 0.0)


func _va(c: Color, vis: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * clampf(vis, 0.0, 1.0))


func _keeper_palette(enter: String) -> Dictionary:
	var coat := Color(0.4, 0.3, 0.2)
	match enter:
		"gunsmith": coat = Color(0.35, 0.3, 0.28)
		"pharmacy": coat = Color(0.85, 0.85, 0.8)
		"store": coat = Color(0.4, 0.45, 0.3)
	return {
		"hat": coat.darkened(0.2), "hat_band": Color(0.4, 0.25, 0.15),
		"coat": coat, "coat_dark": coat.darkened(0.25),
		"shirt": Color(0.8, 0.75, 0.6), "pants": Color(0.3, 0.26, 0.2),
		"skin": Color(0.88, 0.68, 0.5), "bandana": Color(0.7, 0.5, 0.3),
		"belt": Color(0.2, 0.14, 0.09), "buckle": Color(0.85, 0.75, 0.4),
		"boots": Color(0.25, 0.17, 0.1), "hair": Color(0.2, 0.14, 0.09),
	}


func _draw_building(b: Dictionary) -> void:
	if str(b["label"]) == "★ BANQUE ★":
		_draw_bank(b)
		return
	var fr: Rect2 = b["foot"]
	# Intérieur in-map : dessiné AVANT les murs ; il apparaît à mesure que le toit
	# devient transparent (alpha = 1 - opacité du bâtiment).
	if bool(b.get("enterable", false)) and _fade < 0.92:
		_draw_interior(b, 1.0 - _fade)
	var s := _building_style(str(b["label"]))
	# Occlusion : on fade les couleurs sources ; tout ce qui en dérive (darkened/
	# lightened) hérite de l'alpha, donc le bâtiment devient transparent d'un coup.
	s["door"] = _fa(s["door"])
	s["shutter"] = _fa(s["shutter"])
	var wall: Color = _fa(s["wall"])
	var side := wall.darkened(0.24)
	var trim: Color = _fa(s["trim"])
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
	if _horse_ctrl.mounted:
		_draw_mounted(f)
		return
	CharacterArt.draw_person(self, Iso.project(_player_pos), f, CharacterArt.hero_palette(),
			false, false, _walk, 0.0, 0.0)
	# Flash de bouche quand on tire.
	if _muzzle_t > 0.0:
		var mz := Iso.project(_player_pos) + f * 20.0 + Vector2(0, -16)
		draw_circle(mz, 8.0, Color(1.0, 0.9, 0.5, 0.9))
		draw_circle(mz, 4.0, Color(1.0, 1.0, 0.8))


## Tumbleweed qui roule (boule de brindilles qui tourne).
func _draw_tumble(w: Dictionary) -> void:
	var base := Iso.project(w["pos"])
	var sp: float = w["spin"]
	draw_colored_polygon(_diamond_shadow(base, 12.0), Color(0, 0, 0, 0.16))
	var col := Color(0.62, 0.5, 0.28)
	draw_arc(base + Vector2(0, -10), 11.0, 0, TAU, 14, col, 2.0)
	for k in range(7):
		var a := sp + TAU * k / 7.0
		draw_line(base + Vector2(0, -10), base + Vector2(0, -10) + Vector2.RIGHT.rotated(a) * 11.0,
				col.lightened(0.1 if k % 2 == 0 else 0.0), 1.5)


## Chasseur de primes : silhouette en manteau sombre + étoile/marqueur rouge.
func _draw_hunter(h: Dictionary) -> void:
	var pos: Vector2 = h["pos"]
	var f := _screen_facing(pos, h["facing"])
	CharacterArt.draw_person(self, Iso.project(pos), f, _hunter_palette(), true, true, _hint_t * 6.0, 0.0, 0.0)
	# Marqueur de menace flottant.
	var head := Iso.project(pos) + Vector2(0, -54)
	var bob := sin(_hint_t * 5.0 + pos.x) * 2.0
	_text(head + Vector2(0, bob), "❗", 18, Color(1.0, 0.3, 0.25))


## Homme de loi (shérif) lancé après le braquage.
func _draw_lawman(p: Dictionary) -> void:
	var pos: Vector2 = p["pos"]
	var f := _screen_facing(pos, p["facing"])
	CharacterArt.draw_person(self, Iso.project(pos), f, _lawman_palette(), true, true, _hint_t * 7.0, 0.0, 0.0)
	var head := Iso.project(pos) + Vector2(0, -54)
	_text(head, "★", 18, Color(0.95, 0.85, 0.3))


## Bandit qui rôde (gibier à dégommer).
func _draw_bandit(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var f := _screen_facing(pos, (b["vel"] as Vector2))
	var law: bool = b.get("law", false)
	var pal := _lawman_palette() if law else _hunter_palette()
	CharacterArt.draw_person(self, Iso.project(pos), f, pal, true, true, _hint_t * 8.0, 0.0, 0.0)
	# Marqueur au-dessus : étoile de shérif pour les lois, $ pour les bandits.
	if law:
		_text(Iso.project(pos) + Vector2(0, -52), "✦", 15, Color(0.7, 0.85, 1.0))
	else:
		_text(Iso.project(pos) + Vector2(0, -52), "$", 14, Color(0.95, 0.8, 0.3))


## Mini-boss recherché : silhouette plus grande, manteau noir, barre de vie + nom.
func _draw_boss(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var sp := Iso.project(pos)
	var f := _screen_facing(pos, (b["vel"] as Vector2))
	# Aura rouge menaçante + ombre élargie.
	draw_circle(sp + Vector2(0, -2), 26.0, Color(0.7, 0.1, 0.1, 0.18))
	draw_colored_polygon(_diamond_shadow(sp, 16.0), Color(0, 0, 0, 0.28))
	CharacterArt.draw_person(self, sp, f, _boss_palette(), true, true, _hint_t * 9.0, 0.0, 0.0)
	# Barre de vie + nom au-dessus.
	var frac: float = clampf(float(b["hp"]) / float(b["max_hp"]), 0.0, 1.0)
	var head := sp + Vector2(0, -62)
	draw_rect(Rect2(head + Vector2(-34, -6), Vector2(68, 7)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(head + Vector2(-34, -6), Vector2(68.0 * frac, 7)), Color(0.9, 0.2, 0.2))
	_text(head + Vector2(0, -10), "☠ %s" % str(b["name"]), 14, Color(1, 0.85, 0.5))


func _boss_palette() -> Dictionary:
	return {
		"hat": Color(0.07, 0.07, 0.08), "hat_band": Color(0.6, 0.12, 0.12),
		"coat": Color(0.12, 0.11, 0.13), "coat_dark": Color(0.06, 0.05, 0.07),
		"shirt": Color(0.30, 0.10, 0.10), "pants": Color(0.10, 0.09, 0.10),
		"skin": Color(0.82, 0.62, 0.46), "bandana": Color(0.7, 0.12, 0.12),
		"belt": Color(0.10, 0.08, 0.06), "buckle": Color(0.85, 0.7, 0.3),
		"boots": Color(0.10, 0.08, 0.07), "hair": Color(0.10, 0.08, 0.06),
	}


## Garde de banque (riposte pendant le braquage).
func _draw_bank_guard(g: Dictionary) -> void:
	var pos: Vector2 = g["pos"]
	var f := _screen_facing(pos, g["facing"])
	CharacterArt.draw_person(self, Iso.project(pos), f, _lawman_palette(), true, _alarm_on, 0.0, 0.0, 0.0)
	if _alarm_on:
		_text(Iso.project(pos) + Vector2(0, -52), "❗", 16, Color(1.0, 0.3, 0.25))


func _lawman_palette() -> Dictionary:
	return {
		"hat": Color(0.20, 0.22, 0.30), "hat_band": Color(0.7, 0.6, 0.2),
		"coat": Color(0.24, 0.30, 0.45), "coat_dark": Color(0.15, 0.20, 0.32),
		"shirt": Color(0.55, 0.18, 0.16), "pants": Color(0.20, 0.22, 0.30),
		"skin": Color(0.85, 0.65, 0.47), "bandana": Color(0.8, 0.75, 0.7),
		"belt": Color(0.16, 0.12, 0.09), "buckle": Color(0.9, 0.82, 0.4),
		"boots": Color(0.18, 0.13, 0.09), "hair": Color(0.18, 0.13, 0.09),
	}


## Barre de crochetage du coffre (au-dessus de la banque) + "VIDÉ" après.
func _draw_vault_progress() -> void:
	var bank = _bank_dict()
	if bank == null:
		return
	var head := Iso.project(_vault_world(bank)) + Vector2(0, -70)
	if _vault_cracking and _vault_prog < 1.0:
		var w := 90.0
		draw_rect(Rect2(head + Vector2(-w * 0.5, -6), Vector2(w, 12)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(head + Vector2(-w * 0.5, -6), Vector2(w * _vault_prog, 12)), Color(0.95, 0.8, 0.2))
		_text(head + Vector2(0, -14), "CROCHETAGE…", 13, Color(1, 0.9, 0.5))
	elif _heist_done:
		_text(head, "COFFRE VIDÉ", 13, Color(0.95, 0.85, 0.4))


func _hunter_palette() -> Dictionary:
	return {
		"hat": Color(0.16, 0.14, 0.16), "hat_band": Color(0.5, 0.12, 0.10),
		"coat": Color(0.20, 0.18, 0.22), "coat_dark": Color(0.12, 0.11, 0.14),
		"shirt": Color(0.32, 0.16, 0.16), "pants": Color(0.16, 0.15, 0.17),
		"skin": Color(0.82, 0.62, 0.46), "bandana": Color(0.6, 0.15, 0.13),
		"belt": Color(0.10, 0.09, 0.08), "buckle": Color(0.85, 0.78, 0.4),
		"boots": Color(0.12, 0.10, 0.09), "hair": Color(0.12, 0.10, 0.08),
	}


## Joueur à cheval : poussière de galop + cheval orienté + cavalier au-dessus.
func _draw_mounted(face: Vector2) -> void:
	var base := Iso.project(_player_pos)
	var g: float = _horse_ctrl.gallop
	var bob := sin(_ride_walk) * 2.2 * g
	# Poussière soulevée derrière la monture au galop.
	if g > 0.2:
		var back := -face * 18.0
		for i in range(2):
			var pp := base + back + Vector2(_rng.randf_range(-7, 7), _rng.randf_range(-2, 5))
			draw_circle(pp, _rng.randf_range(3.0, 6.0), Color(0.74, 0.65, 0.49, 0.22 * g))
	draw_colored_polygon(_diamond_shadow(base, 22.0), Color(0, 0, 0, 0.20))
	var flip := -1.0 if face.x > 0.1 else 1.0
	_draw_horse_screen(base + Vector2(0, bob), flip)
	CharacterArt.draw_person(self, base + Vector2(0, -17 + bob), face,
			CharacterArt.hero_palette(), false, false, 0.0, 0.0, 0.0)


## Cheval dessiné en espace écran (orienté par `flip`), pour la monture du joueur.
func _draw_horse_screen(base: Vector2, flip: float) -> void:
	var body := Color(0.36, 0.23, 0.13)
	var dark := body.darkened(0.28)
	for dx in [-9.0, -3.0, 4.0, 10.0]:
		draw_line(base + Vector2(dx * flip, -12), base + Vector2((dx + 1.0) * flip, 2), dark, 3.0)
	var bl := base + Vector2(-12 * flip, -16)
	var brr := base + Vector2(12 * flip, -16)
	draw_line(bl, brr, body, 14.0)
	draw_circle(bl, 7.0, body)
	draw_circle(brr, 7.0, body)
	draw_line(brr + Vector2(3 * flip, -3), base + Vector2(18 * flip, 3), dark, 3.0)
	var neck := bl + Vector2(1 * flip, -3)
	var head := bl + Vector2(-11 * flip, -16)
	draw_line(neck, head, body, 7.0)
	draw_circle(head, 4.5, body)
	draw_line(head, head + Vector2(-5 * flip, 2), body, 5.0)
	draw_line(head + Vector2(1 * flip, -3), head + Vector2(3 * flip, -7), body, 2.0)
	draw_line(neck + Vector2(-1 * flip, -3), head + Vector2(3 * flip, 3), dark, 3.0)
	draw_circle(head + Vector2(-2 * flip, -1), 1.0, Color(0.05, 0.04, 0.03))


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

	# Bandeau PRIME / chasseurs de primes (lot 14), centré en haut.
	_wanted_label = Label.new()
	_wanted_label.add_theme_font_size_override("font_size", 18)
	_wanted_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	_wanted_label.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.02))
	_wanted_label.add_theme_constant_override("outline_size", 5)
	_wanted_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_wanted_label.position = Vector2(0, 44)
	_wanted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wanted_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_wanted_label)

	# PV (affiché seulement pendant le braquage sous le feu).
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 22)
	_hp_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.22))
	_hp_label.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.02))
	_hp_label.add_theme_constant_override("outline_size", 5)
	_hp_label.position = Vector2(16, 70)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hp_label)

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
