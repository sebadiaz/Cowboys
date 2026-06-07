extends Node
## GameManager (autoload)
## État global et transitions de scènes. Transporte le résultat de la mission
## jusqu'à l'écran de résultat.

const SCENE_MAIN_MENU := "res://scenes/MainMenu.tscn"
const SCENE_TOWN := "res://scenes/levels/Town.tscn"
const SCENE_SALOON := "res://scenes/levels/Saloon.tscn"
const SCENE_MISSION := "res://scenes/MissionRoot.tscn"
const SCENE_RESULT := "res://scenes/ResultScreen.tscn"
const SCENE_LEVEL_SELECT := "res://scenes/LevelSelect.tscn"
const SCENE_SHOP := "res://scenes/ShopScreen.tscn"
const SCENE_SETTINGS := "res://scenes/SettingsScreen.tscn"
const SCENE_WORLD_MAP := "res://scenes/WorldMap.tscn"

## Villes du territoire — GÉNÉRÉES PROCÉDURALEMENT (déterministe, même carte à
## chaque lancement). ~20 villes le long d'une piste sinueuse traversant des
## biomes (désert → canyon → plaines → neige). Chaque ville a sa banque (mission),
## sa difficulté croissante et son ambiance. Rempli par `_generate_towns()`.
const TOWN_COUNT := 20
const TOWN_SEED := 0xC0FFEE
var TOWNS: Array = []

const LEVEL_COUNT := 3
## Niveau en cours de jeu (1..LEVEL_COUNT).
var current_level: int = 1
## Ville courante (index 1-based dans TOWNS).
var current_town: int = 1
## Mission procédurale (banque générée pour la ville) vs mission JSON (niveau rapide).
var procedural := false
var mission_seed := 0
var mission_biome := "desert"
## Position de réapparition en ville (ex. en sortant du saloon). Zero = défaut.
var town_return_pos := Vector2.ZERO
## La boutique a-t-elle été ouverte depuis la ville (retour en ville) ?
var shop_from_town := false

## Mode "assist" (prototype) activé par défaut : plus de PV, alarme plus lente,
## gardes moins agressifs, contact non létal. Basculable depuis le menu.
var assist := true

## Cycle jour/nuit : world_time ∈ [0,1) (0 = minuit, 0.5 = midi). Avance en
## continu et persiste entre les scènes. Le rendu lit ambient_color()/darkness().
const DAY_LENGTH := 160.0   # secondes pour un cycle complet
var world_time := 0.34      # on démarre en matinée

const _SKY := [
	[0.00, Color(0.30, 0.32, 0.58)], [0.22, Color(0.55, 0.45, 0.55)],
	[0.27, Color(0.98, 0.72, 0.55)], [0.36, Color(1.0, 0.96, 0.90)],
	[0.50, Color(1.0, 1.0, 1.0)],    [0.70, Color(1.0, 0.93, 0.84)],
	[0.79, Color(0.97, 0.60, 0.42)], [0.88, Color(0.50, 0.40, 0.58)],
	[1.00, Color(0.30, 0.32, 0.58)],
]


func _ready() -> void:
	_generate_towns()


## Génère ~20 villes de façon DÉTERMINISTE (même carte à chaque lancement) le long
## d'une piste sinueuse, à travers des biomes, difficulté croissante.
func _generate_towns() -> void:
	TOWNS.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED
	var pre := ["Red", "Dry", "Dead", "Silver", "Gold", "Dusty", "Coyote", "Snake",
		"Black", "Lone", "Broken", "Boot", "Iron", "Buzzard", "Cactus", "Sage",
		"Rattlesnake", "Bone", "Crooked", "Hangman", "Tumble", "Copper", "Ghost", "Lost"]
	var suf := ["Gulch", "Creek", "Rock", "Springs", "Flats", "Ridge", "Hollow", "Mesa",
		"Bend", "Canyon", "Wells", "City", "Junction", "Crossing", "Fork", "Butte",
		"Hill", "Camp", "Ford", "Pass", "Gap", "Bluff"]
	var tier_name := {1: "Petite banque", 2: "Banque de comté", 3: "Grande banque"}
	var used := {}
	for i in range(TOWN_COUNT):
		var t := float(i) / float(TOWN_COUNT - 1)
		var x := lerpf(0.07, 0.93, t)
		var y := 0.50 + 0.30 * sin(t * PI * 3.2 + 0.6) + rng.randf_range(-0.045, 0.045)
		y = clampf(y, 0.18, 0.84)
		var lvl := clampi(1 + int(t * 2.999), 1, LEVEL_COUNT)
		var theme := _biome_for(t)
		# Nom procédural unique.
		var nm := "Ville %d" % (i + 1)
		for _a in range(40):
			var cand := "%s %s" % [pre[rng.randi() % pre.size()], suf[rng.randi() % suf.size()]]
			if not used.has(cand):
				used[cand] = true
				nm = cand
				break
		var stars := ""
		for _k in range(lvl):
			stars += "★"
		TOWNS.append({
			"name": nm, "level": lvl, "theme": theme, "pos": [x, y],
			"tag": "%s %s" % [stars, tier_name[lvl]],
		})


## Biome (ambiance) selon l'avancée sur la piste — aligné sur les régions de la carte.
func _biome_for(t: float) -> String:
	if t < 0.22:
		return "desert"
	elif t < 0.42:
		return "canyon"
	elif t < 0.60:
		return "plains"
	elif t < 0.80:
		return "snow"
	return "night"


func _process(delta: float) -> void:
	world_time = fposmod(world_time + delta / DAY_LENGTH, 1.0)


## Teinte d'ambiance (multiplicateur de canvas) selon l'heure.
func ambient_color() -> Color:
	for i in range(_SKY.size() - 1):
		var a: Array = _SKY[i]
		var b: Array = _SKY[i + 1]
		if world_time <= float(b[0]):
			var k := (world_time - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return (a[1] as Color).lerp(b[1] as Color, clampf(k, 0.0, 1.0))
	return _SKY[-1][1]


## Obscurité 0 (plein jour) → ~0.7 (nuit), pour allumer lampes/halos.
func darkness() -> float:
	return clampf(1.0 - ambient_color().g, 0.0, 1.0)


## Vrai s'il fait assez sombre pour allumer les lumières.
func is_dark() -> bool:
	return darkness() > 0.12

## Résultat de la dernière mission jouée, lu par ResultScreen.
var last_result := {
	"success": false,
	"loot_value": 0,
	"loot_bags": 0,
	"money_earned": 0,
	"score": {"loot": 0, "stealth": 0, "time": 0, "total": 0},
}


func goto_main_menu() -> void:
	_change_scene(SCENE_MAIN_MENU)


func goto_level_select() -> void:
	_change_scene(SCENE_LEVEL_SELECT)


func goto_settings() -> void:
	_change_scene(SCENE_SETTINGS)


## Entre dans le saloon (depuis la ville).
func goto_saloon() -> void:
	_change_scene(SCENE_SALOON)


## Ouvre la boutique d'upgrades (depuis le menu / l'écran de résultat).
func goto_shop() -> void:
	shop_from_town = false
	_change_scene(SCENE_SHOP)


## Ouvre la boutique depuis le Magasin de la ville (le retour ramène en ville).
func goto_shop_from_town(pos := Vector2.ZERO) -> void:
	shop_from_town = true
	town_return_pos = pos
	_change_scene(SCENE_SHOP)


## Quitte la boutique : retour en ville si on y était entré, sinon au menu.
func leave_shop() -> void:
	if shop_from_town:
		shop_from_town = false
		_change_scene(SCENE_TOWN)
	else:
		_change_scene(SCENE_MAIN_MENU)


## Revient en ville à une position donnée (ex. devant la porte du saloon).
func return_to_town(pos := Vector2.ZERO) -> void:
	town_return_pos = pos
	_change_scene(SCENE_TOWN)


## Le bouton "Jouer" amène à la CARTE DU MONDE : on choisit sa ville, on y rejoint
## la banque à pied.
func start_town() -> void:
	goto_world_map()


## Ouvre la carte du monde (choix de la ville).
func goto_world_map() -> void:
	_change_scene(SCENE_WORLD_MAP)


## Définition d'une ville (index 1-based, borné).
func town_def(idx: int) -> Dictionary:
	return TOWNS[clampi(idx - 1, 0, TOWNS.size() - 1)]


func current_town_def() -> Dictionary:
	return town_def(current_town)


## Une ville est jouable si elle a une banque débloquée.
func town_unlocked(idx: int) -> bool:
	return idx >= 1 and idx <= TOWNS.size() and SaveManager.is_town_unlocked(idx)


## Voyage vers une ville : règle ville + niveau, puis charge la scène de ville.
func travel_to_town(idx: int) -> void:
	var t := town_def(idx)
	var lvl := int(t.get("level", 0))
	if lvl < 1:
		return
	current_town = idx
	current_level = clampi(lvl, 1, LEVEL_COUNT)
	town_return_pos = Vector2.ZERO
	# Banque PROCÉDURALE propre à cette ville (graine déterministe + biome).
	procedural = true
	mission_seed = idx * 1009 + 7
	mission_biome = str(t.get("theme", "desert"))
	_change_scene(SCENE_TOWN)


## Lance directement un niveau (depuis la sélection de niveaux ou "suivant").
func play_level(level: int) -> void:
	current_level = clampi(level, 1, LEVEL_COUNT)
	procedural = false      # niveau rapide = mission JSON figée
	_change_scene(SCENE_MISSION)


func start_mission() -> void:
	_change_scene(SCENE_MISSION)


## Appelé par mission_manager à la fin d'une mission. `score` détaille le calcul
## (butin + discrétion + temps) ; l'argent gagné = total du score si réussite.
func finish_mission(success: bool, loot_value: int, loot_bags: int, score: Dictionary = {}) -> void:
	if score.is_empty():
		score = {"loot": loot_value, "stealth": 0, "time": 0, "total": loot_value}
	var money_earned: int = int(round(int(score.get("total", loot_value)) * SaveManager.notoriety_reward_mult())) if success else 0
	last_result = {
		"success": success,
		"loot_value": loot_value,
		"loot_bags": loot_bags,
		"money_earned": money_earned,
		"score": score,
	}
	if success:
		SaveManager.register_success(money_earned)
		# Débloque le niveau suivant.
		if current_level < LEVEL_COUNT:
			SaveManager.unlock_level(current_level + 1)
		# Débloque la ville suivante sur la carte du monde.
		if current_town < TOWNS.size():
			SaveManager.unlock_town(current_town + 1)
		SaveManager.gain_notoriety()
	else:
		SaveManager.lose_notoriety()
	_change_scene(SCENE_RESULT)


## Métadonnées d'un niveau (nom + difficulté) lues dans son fichier de données.
func level_info(level: int) -> Dictionary:
	var path := "res://data/mission_%02d.json" % clampi(level, 1, LEVEL_COUNT)
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(d) == TYPE_DICTIONARY:
				return {"name": str(d.get("name", "Banque %d" % level)),
						"difficulty": str(d.get("difficulty", ""))}
	return {"name": "Banque %d" % level, "difficulty": ""}


func _change_scene(path: String) -> void:
	# On s'assure que le jeu n'est pas en pause lors d'un changement de scène.
	get_tree().paused = false
	Engine.time_scale = 1.0   # jamais de ralenti résiduel entre scènes
	get_tree().change_scene_to_file(path)
