extends Node
## alarm_system.gd
## Jauge d'alarme partagée 0 → 100. Les gardes y ajoutent de la détection quand
## ils voient le joueur ; elle décroît lentement sinon. À 100 : alerte globale.

signal alarm_changed(value: float)
signal global_alert_triggered()

const MAX_ALARM := 100.0
const DECAY_PER_SEC := 8.0

var alarm: float = 0.0
var global_alert: bool = false


func _process(delta: float) -> void:
	if global_alert:
		return
	if alarm > 0.0:
		alarm = max(0.0, alarm - DECAY_PER_SEC * delta)
		alarm_changed.emit(alarm)


## Appelé par les gardes : ajoute de la détection à la jauge.
func add_detection(amount: float) -> void:
	if global_alert:
		return
	alarm = clamp(alarm + amount, 0.0, MAX_ALARM)
	alarm_changed.emit(alarm)
	if alarm >= MAX_ALARM:
		_trigger_global_alert()


func _trigger_global_alert() -> void:
	if global_alert:
		return
	global_alert = true
	alarm = MAX_ALARM
	alarm_changed.emit(alarm)
	global_alert_triggered.emit()


func get_ratio() -> float:
	return alarm / MAX_ALARM
