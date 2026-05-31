extends Node
## SaveManager (autoload)
## Sauvegarde locale simple dans user://save.json.
## Persiste l'argent total et le nombre de missions réussies.

const SAVE_PATH := "user://save.json"

var total_money: int = 0
var missions_completed: int = 0


func _ready() -> void:
	load_game()


## Charge la sauvegarde. Si le fichier est absent ou corrompu, on repart
## sur des valeurs par défaut sans planter.
func load_game() -> void:
	total_money = 0
	missions_completed = 0
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	total_money = int(data.get("total_money", 0))
	missions_completed = int(data.get("missions_completed", 0))


## Écrit la sauvegarde sur disque.
func save_game() -> void:
	var data := {
		"total_money": total_money,
		"missions_completed": missions_completed,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: impossible d'ouvrir %s en écriture." % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


## Enregistre la récompense d'une mission réussie.
func register_success(money_earned: int) -> void:
	total_money += max(0, money_earned)
	missions_completed += 1
	save_game()
