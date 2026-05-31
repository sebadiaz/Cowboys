extends Control
## main_menu.gd
## Menu principal : titre, bouton Jouer, rappel des contrôles et magot total.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.85, 0.74, 0.53)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-220, -200)
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)

	box.add_child(_label("DUST & DOLLARS", 52, Color(0.35, 0.2, 0.1)))
	box.add_child(_label("Braquage de banque — Far West", 20, Color(0.4, 0.28, 0.16)))

	box.add_child(_spacer(20))

	var play := Button.new()
	play.text = "JOUER LE BRAQUAGE"
	play.custom_minimum_size = Vector2(440, 56)
	play.pressed.connect(func() -> void: GameManager.start_mission())
	box.add_child(play)

	box.add_child(_spacer(10))

	box.add_child(_label(
		"Clavier : WASD/ZQSD bouger · E interagir · Échap pause", 16,
		Color(0.3, 0.2, 0.12)))
	box.add_child(_label(
		"Mobile : joystick (gauche) + bouton E (droite)", 16,
		Color(0.3, 0.2, 0.12)))

	box.add_child(_spacer(16))

	box.add_child(_label(
		"Magot total : %d $   ·   Missions réussies : %d" % [
			SaveManager.total_money, SaveManager.missions_completed], 18,
		Color(0.3, 0.2, 0.12)))


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
