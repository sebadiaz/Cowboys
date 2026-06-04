extends Node
## SaveManager (autoload)
## Sauvegarde locale simple dans user://save.json.
## Persiste l'argent total, les missions réussies et les upgrades achetés.
## Rétrocompatible : une vieille save sans "upgrades" se charge sans planter.

const SAVE_PATH := "user://save.json"

## Définition des upgrades : nom, description, coûts par niveau (taille = max).
const UPGRADE_DEFS := {
	"speed":   {"name": "Bottes véloces",  "desc": "Vitesse +6% / niveau",        "cost": [300, 600, 1000, 1600]},
	"reload":  {"name": "Barillet huilé",  "desc": "Recharge -12% / niveau",      "cost": [300, 600, 1000]},
	"safe":    {"name": "Crochets fins",   "desc": "Coffre -15% plus vite / niv", "cost": [350, 700, 1200]},
	"stealth": {"name": "Pas feutrés",     "desc": "Alarme monte -15% / niveau",  "cost": [350, 700, 1200, 1800]},
}
## Ordre d'affichage stable dans la boutique.
const UPGRADE_ORDER := ["speed", "reload", "safe", "stealth"]

var total_money: int = 0
var missions_completed: int = 0
var upgrades: Dictionary = {}
var levels_unlocked: int = 1   # niveaux débloqués (1 = seul le 1er)


func _ready() -> void:
	load_game()


## Charge la sauvegarde. Si le fichier est absent ou corrompu, on repart
## sur des valeurs par défaut sans planter.
func load_game() -> void:
	total_money = 0
	missions_completed = 0
	upgrades = _default_upgrades()
	levels_unlocked = 1
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
	levels_unlocked = maxi(1, int(data.get("levels_unlocked", 1)))
	# Upgrades : on ne lit que les clés connues, bornées à leur max.
	var saved: Variant = data.get("upgrades", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for key in UPGRADE_DEFS.keys():
			upgrades[key] = clampi(int(saved.get(key, 0)), 0, max_level(key))


func _default_upgrades() -> Dictionary:
	var d := {}
	for key in UPGRADE_DEFS.keys():
		d[key] = 0
	return d


## Écrit la sauvegarde sur disque.
func save_game() -> void:
	var data := {
		"total_money": total_money,
		"missions_completed": missions_completed,
		"upgrades": upgrades,
		"levels_unlocked": levels_unlocked,
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


## Débloque (au moins) jusqu'au niveau donné.
func unlock_level(level: int) -> void:
	if level > levels_unlocked:
		levels_unlocked = level
		save_game()


func is_level_unlocked(level: int) -> bool:
	return level <= levels_unlocked


# --- Upgrades ---

func max_level(key: String) -> int:
	var def: Dictionary = UPGRADE_DEFS.get(key, {})
	return (def.get("cost", []) as Array).size()


func get_level(key: String) -> int:
	return int(upgrades.get(key, 0))


## Coût du prochain niveau, ou -1 si déjà au maximum.
func next_cost(key: String) -> int:
	var lvl := get_level(key)
	if lvl >= max_level(key):
		return -1
	return int(UPGRADE_DEFS[key]["cost"][lvl])


func can_buy(key: String) -> bool:
	var cost := next_cost(key)
	return cost >= 0 and total_money >= cost


## Achète un niveau d'upgrade. Retourne true si l'achat a réussi.
func buy(key: String) -> bool:
	if not can_buy(key):
		return false
	total_money -= next_cost(key)
	upgrades[key] = get_level(key) + 1
	save_game()
	return true


# Multiplicateurs appliqués en mission.
func speed_mult() -> float:
	return 1.0 + 0.06 * get_level("speed")

func reload_mult() -> float:
	return maxf(0.4, 1.0 - 0.12 * get_level("reload"))

func safe_mult() -> float:
	return maxf(0.4, 1.0 - 0.15 * get_level("safe"))

func stealth_mult() -> float:
	return maxf(0.3, 1.0 - 0.15 * get_level("stealth"))
