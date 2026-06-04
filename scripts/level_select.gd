extends Control
## level_select.gd
## Choix du braquage : liste les niveaux (déverrouillés au fil des réussites).
## Un niveau verrouillé est grisé. UI construite en code (desktop + mobile).

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.12, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	box.add_child(_title("CHOISIS TON BRAQUAGE", 34, Color(0.95, 0.8, 0.35)))
	box.add_child(_title("Magot : %d $" % SaveManager.total_money, 18, Color(0.9, 0.9, 0.6)))
	box.add_child(_spacer(8))

	for lvl in range(1, GameManager.LEVEL_COUNT + 1):
		box.add_child(_level_button(lvl))

	box.add_child(_spacer(10))
	var back := Button.new()
	back.text = "← Retour au menu"
	back.custom_minimum_size = Vector2(520, 50)
	back.pressed.connect(func(): GameManager.goto_main_menu())
	box.add_child(back)


func _level_button(lvl: int) -> Button:
	var info := GameManager.level_info(lvl)
	var unlocked := SaveManager.is_level_unlocked(lvl)
	var b := Button.new()
	b.custom_minimum_size = Vector2(520, 64)
	if unlocked:
		b.text = "Niveau %d — %s\n(%s)" % [lvl, info["name"], info["difficulty"]]
		b.pressed.connect(func(): GameManager.play_level(lvl))
	else:
		b.text = "🔒 Niveau %d — verrouillé\n(réussis le niveau %d)" % [lvl, lvl - 1]
		b.disabled = true
	return b


func _title(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
