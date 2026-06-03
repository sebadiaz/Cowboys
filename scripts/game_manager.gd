extends Node
## GameManager (autoload)
## État global et transitions de scènes. Transporte le résultat de la mission
## jusqu'à l'écran de résultat.

const SCENE_MAIN_MENU := "res://scenes/MainMenu.tscn"
const SCENE_TOWN := "res://scenes/levels/Town.tscn"
const SCENE_MISSION := "res://scenes/MissionRoot.tscn"
const SCENE_RESULT := "res://scenes/ResultScreen.tscn"

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


## Le bouton "Jouer" amène d'abord en ville (on rejoint la banque à pied).
func start_town() -> void:
	_change_scene(SCENE_TOWN)


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
	_change_scene(SCENE_RESULT)


func _change_scene(path: String) -> void:
	# On s'assure que le jeu n'est pas en pause lors d'un changement de scène.
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
