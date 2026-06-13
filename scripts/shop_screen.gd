extends Control
## shop_screen.gd
## Boutique d'upgrades : on dépense le magot total pour améliorer le cowboy.
## Les niveaux sont persistés par SaveManager (user://save.json) et appliqués
## en mission. UI construite en code (robuste desktop + mobile).

var _money_label: Label
var _rows: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	UiTheme.add_backdrop(self, "shop")

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 24)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	col.add_child(_title(_shop_title(), 36, Color(0.95, 0.8, 0.35)))
	col.add_child(_title(_shop_sub(), 16, Color(0.82, 0.78, 0.6)))
	_money_label = _title("Magot : %d $" % SaveManager.total_money, 22, Color(0.9, 0.9, 0.6))
	col.add_child(_money_label)

	# Liste défilante (sécurité petits écrans).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_rows)

	var back := Button.new()
	back.text = "← Retour à la ville" if GameManager.shop_from_town else "← Retour au menu"
	back.custom_minimum_size = Vector2(0, 54)
	back.pressed.connect(func(): GameManager.leave_shop())
	col.add_child(back)

	_rebuild()


func _rebuild() -> void:
	for c in _rows.get_children():
		c.queue_free()
	_money_label.text = "Magot : %d $" % SaveManager.total_money
	var cat := GameManager.shop_category
	for key in SaveManager.UPGRADE_ORDER:
		if cat != "" and str(SaveManager.UPGRADE_DEFS[key].get("store", "")) != cat:
			continue
		_rows.add_child(_make_row(key))


## Titre / sous-titre / sortie selon le commerce (lot 13).
func _shop_title() -> String:
	match GameManager.shop_category:
		"gunsmith": return "🔫 ARMURIER"
		"pharmacy": return "➕ CABINET DU DOC"
		"store": return "🛒 MAGASIN GÉNÉRAL"
		_: return "🛒 BOUTIQUE DU HORS-LA-LOI"


func _shop_sub() -> String:
	match GameManager.shop_category:
		"gunsmith": return "Armes & munitions — recharge, barillet, cadence"
		"pharmacy": return "Soins — vitalité, résistance aux balles"
		"store": return "Équipement — bottes, crochets, discrétion, sacoches"
		_: return "Tout l'équipement du hors-la-loi"


func _make_row(key: String) -> Control:
	var def: Dictionary = SaveManager.UPGRADE_DEFS[key]
	var lvl := SaveManager.get_level(key)
	var maxl := SaveManager.max_level(key)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.09, 0.06, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = (Color(0.5, 0.8, 0.4) if SaveManager.can_buy(key) else Color(0.5, 0.38, 0.22))
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(_lbl("%s   %s" % [def["name"], _dots(lvl, maxl)], 22, Color(1, 1, 1)))
	info.add_child(_lbl(def["desc"], 15, Color(0.8, 0.78, 0.7)))

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(190, 64)
	var cost := SaveManager.next_cost(key)
	if cost < 0:
		buy.text = "MAX"
		buy.disabled = true
	else:
		buy.text = "Acheter\n%d $" % cost
		buy.disabled = not SaveManager.can_buy(key)
		buy.pressed.connect(func(): _on_buy(key))
	row.add_child(buy)
	return panel


func _on_buy(key: String) -> void:
	if SaveManager.buy(key):
		AudioManager.play("pickup")
	else:
		AudioManager.play("click")
	_rebuild()


func _dots(lvl: int, maxl: int) -> String:
	var s := ""
	for i in range(maxl):
		s += "●" if i < lvl else "○"
	return s


func _title(text: String, font_size: int, color: Color) -> Label:
	var l := _lbl(text, font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _lbl(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
