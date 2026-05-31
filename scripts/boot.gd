extends Control
## boot.gd
## Écran de démarrage. Les autoloads (dont SaveManager) sont déjà prêts ;
## on affiche un court splash puis on bascule vers le menu principal.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.85, 0.74, 0.53)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "DUST & DOLLARS"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.35, 0.2, 0.1))
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-260, -30)
	title.size = Vector2(520, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	await get_tree().create_timer(0.8).timeout
	GameManager.goto_main_menu()
