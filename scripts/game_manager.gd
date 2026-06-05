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

const LEVEL_COUNT := 3
## Niveau en cours de jeu (1..LEVEL_COUNT).
var current_level: int = 1
## Position de réapparition en ville (ex. en sortant du saloon). Zero = défaut.
var town_return_pos := Vector2.ZERO

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


## Entre dans le saloon (depuis la ville).
func goto_saloon() -> void:
	_change_scene(SCENE_SALOON)


## Revient en ville à une position donnée (ex. devant la porte du saloon).
func return_to_town(pos := Vector2.ZERO) -> void:
	town_return_pos = pos
	_change_scene(SCENE_TOWN)


## Le bouton "Jouer" amène d'abord en ville (on rejoint la banque à pied).
## On (re)prend le dernier niveau débloqué par défaut.
func start_town() -> void:
	current_level = clampi(SaveManager.levels_unlocked, 1, LEVEL_COUNT)
	_change_scene(SCENE_TOWN)


## Lance directement un niveau (depuis la sélection de niveaux ou "suivant").
func play_level(level: int) -> void:
	current_level = clampi(level, 1, LEVEL_COUNT)
	_change_scene(SCENE_MISSION)


func start_mission() -> void:
	_change_scene(SCENE_MISSION)


## Appelé par mission_manager à la fin d'une mission. `score` détaille le calcul
## (butin + discrétion + temps) ; l'argent gagné = total du score si réussite.
func finish_mission(success: bool, loot_value: int, loot_bags: int, score: Dictionary = {}) -> void:
	if score.is_empty():
		score = {"loot": loot_value, "stealth": 0, "time": 0, "total": loot_value}
	var money_earned: int = int(score.get("total", loot_value)) if success else 0
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
	get_tree().change_scene_to_file(path)
