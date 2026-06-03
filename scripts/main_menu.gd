extends Control
## main_menu.gd
## Menu principal : titre, bouton Jouer, rappel des contrôles et magot total.
## Layout via conteneurs (robuste sur desktop et mobile, quelle que soit la taille).

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.85, 0.74, 0.53)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	box.add_child(_label("DUST & DOLLARS", 52, Color(0.35, 0.2, 0.1)))
	box.add_child(_label("Braquage de banque — Far West", 20, Color(0.4, 0.28, 0.16)))

	box.add_child(_spacer(20))

	var play := Button.new()
	play.text = "JOUER LE BRAQUAGE"
	play.custom_minimum_size = Vector2(460, 60)
	play.pressed.connect(_on_play)
	box.add_child(play)

	var shop := Button.new()
	shop.text = "🛒 BOUTIQUE (upgrades)"
	shop.custom_minimum_size = Vector2(460, 50)
	shop.pressed.connect(_on_shop)
	box.add_child(shop)

	var visual := Button.new()
	visual.text = "Voir le décor banque (test)"
	visual.custom_minimum_size = Vector2(460, 46)
	visual.pressed.connect(_on_visual_test)
	box.add_child(visual)

	box.add_child(_spacer(10))

	box.add_child(_label(
		"Clavier : WASD/ZQSD bouger · Espace/clic TIRER · E interagir · Échap pause", 15,
		Color(0.3, 0.2, 0.12)))
	box.add_child(_label(
		"Mobile : joystick (gauche) + boutons TIR et E (droite)", 16,
		Color(0.3, 0.2, 0.12)))

	box.add_child(_spacer(16))

	box.add_child(_label(
		"Magot total : %d $   ·   Missions réussies : %d" % [
			SaveManager.total_money, SaveManager.missions_completed], 18,
		Color(0.3, 0.2, 0.12)))


func _on_play() -> void:
	GameManager.start_town()


func _on_shop() -> void:
	get_tree().change_scene_to_file("res://scenes/ShopScreen.tscn")


func _on_visual_test() -> void:
	get_tree().change_scene_to_file("res://scenes/levels/BankVisualTest.tscn")


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(460, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
