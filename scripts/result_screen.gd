extends Control
## result_screen.gd
## Écran de résultat affiché après une mission. Lit GameManager.last_result et
## les totaux de SaveManager. Boutons : Rejouer / Menu principal.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.09, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var r: Dictionary = GameManager.last_result
	var success: bool = bool(r.get("success", false))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-220, -180)
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)

	var title := _label("MISSION RÉUSSIE !" if success else "ÉCHEC DU BRAQUAGE", 40)
	title.add_theme_color_override("font_color",
		Color(0.4, 0.9, 0.4) if success else Color(0.95, 0.4, 0.35))
	box.add_child(title)

	var subtitle := _label(
		"Tu t'es enfui avec le butin !" if success else "Repéré par les gardes...", 18)
	box.add_child(subtitle)

	box.add_child(_spacer(10))

	box.add_child(_label("Sacs récupérés : %d / 3" % int(r.get("loot_bags", 0)), 20))
	box.add_child(_label("Butin de la mission : %d $" % int(r.get("loot_value", 0)), 20))
	box.add_child(_label("Argent gagné : %d $" % int(r.get("money_earned", 0)), 20))

	box.add_child(_spacer(8))

	box.add_child(_label("Magot total : %d $" % SaveManager.total_money, 18))
	box.add_child(_label("Missions réussies : %d" % SaveManager.missions_completed, 18))

	box.add_child(_spacer(16))

	var retry := Button.new()
	retry.text = "Rejouer la mission"
	retry.custom_minimum_size = Vector2(440, 50)
	retry.pressed.connect(func() -> void: GameManager.start_mission())
	box.add_child(retry)

	var menu := Button.new()
	menu.text = "Menu principal"
	menu.custom_minimum_size = Vector2(440, 50)
	menu.pressed.connect(func() -> void: GameManager.goto_main_menu())
	box.add_child(menu)


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
