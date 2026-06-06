extends Node
func _ready()->void:
	var tw=load("res://scenes/levels/Town.tscn").instantiate()
	add_child(tw)
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("res://_town.png")
	get_tree().quit()
