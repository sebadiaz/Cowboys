extends Control
## result_screen.gd
## Écran de résultat affiché après une mission. Lit GameManager.last_result et
## les totaux de SaveManager. Boutons : Rejouer / Menu principal.
## Layout via conteneurs (robuste desktop + mobile).

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.09, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var r: Dictionary = GameManager.last_result
	var success: bool = bool(r.get("success", false))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := _label("MISSION RÉUSSIE !" if success else "ÉCHEC DU BRAQUAGE", 40)
	title.add_theme_color_override("font_color",
		Color(0.4, 0.9, 0.4) if success else Color(0.95, 0.4, 0.35))
	box.add_child(title)

	# Niveau joué.
	var lvl_info := GameManager.level_info(GameManager.current_level)
	var sub := _label("Niveau %d — %s" % [GameManager.current_level, lvl_info["name"]], 18)
	sub.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	box.add_child(sub)

	box.add_child(_label(
		"Tu t'es enfui avec le butin !" if success else "Repéré par les gardes...", 18))

	box.add_child(_spacer(10))

	box.add_child(_label("Sacs récupérés : %d" % int(r.get("loot_bags", 0)), 20))

	# Détail du score (butin + discrétion + temps).
	var score: Dictionary = r.get("score", {})
	if success and not score.is_empty():
		box.add_child(_spacer(4))
		box.add_child(_row("Butin", int(score.get("loot", 0))))
		box.add_child(_row("Bonus discrétion", int(score.get("stealth", 0))))
		box.add_child(_row("Bonus rapidité", int(score.get("time", 0))))
		if int(score.get("contract", 0)) > 0:
			box.add_child(_row("Prime de contrat", int(score.get("contract", 0))))
		var total := _label("TOTAL GAGNÉ : %d $" % int(r.get("money_earned", 0)), 26)
		total.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		box.add_child(total)
	else:
		box.add_child(_label("Butin perdu : %d $" % int(r.get("loot_value", 0)), 20))
		box.add_child(_label("Argent gagné : 0 $", 20))

	box.add_child(_spacer(8))

	box.add_child(_label("Magot total : %d $" % SaveManager.total_money, 18))
	box.add_child(_label("Missions réussies : %d" % SaveManager.missions_completed, 18))

	box.add_child(_spacer(16))

	# Niveau suivant (si réussite et qu'il en reste un).
	if success and GameManager.current_level < GameManager.LEVEL_COUNT:
		var nxt := Button.new()
		var ni := GameManager.level_info(GameManager.current_level + 1)
		nxt.text = "➡ Niveau suivant : %s" % ni["name"]
		nxt.custom_minimum_size = Vector2(460, 54)
		nxt.pressed.connect(func(): GameManager.play_level(GameManager.current_level + 1))
		box.add_child(nxt)

	var retry := Button.new()
	retry.text = "Rejouer le braquage"
	retry.custom_minimum_size = Vector2(460, 52)
	retry.pressed.connect(_on_retry)
	box.add_child(retry)

	var shop := Button.new()
	shop.text = "🛒 Boutique (dépenser le magot)"
	shop.custom_minimum_size = Vector2(460, 50)
	shop.pressed.connect(_on_shop)
	box.add_child(shop)

	var menu := Button.new()
	menu.text = "Menu principal"
	menu.custom_minimum_size = Vector2(460, 50)
	menu.pressed.connect(_on_menu)
	box.add_child(menu)


func _on_retry() -> void:
	GameManager.start_mission()


func _on_shop() -> void:
	GameManager.goto_shop()


func _on_menu() -> void:
	GameManager.goto_main_menu()


## Ligne "Libellé .......... +N $" pour le détail du score.
func _row(label: String, amount: int) -> Label:
	return _label("%s : +%d $" % [label, amount], 19)


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(460, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
