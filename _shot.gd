extends Node
var ms
func _ready() -> void:
	ms = load("res://scenes/MissionRoot.tscn").instantiate()
	add_child(ms)
	await get_tree().create_timer(0.6).timeout
	print("ZOOM=", ms._renderer.scale.x, " CAMPOS=", ms._renderer.position, " PLAYER=", ms.player.global_position)
	get_viewport().get_texture().get_image().save_png("res://_land.png")
	get_tree().quit()
