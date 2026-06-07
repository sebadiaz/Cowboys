extends Control
## crew_screen.gd
## "Monte ton équipe" pour l'ATTAQUE DE LA DILIGENCE : embauche des hors-la-loi
## avec ton magot (jusqu'à 3), chacun apporte un atout, puis lance l'assaut.
## Coéquipiers combattants tirent à tes côtés ; toubib/éclaireur/artificier = bonus.

var _list: VBoxContainer
var _header: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.17, 0.12, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	box.add_child(_title("🐎 ATTAQUE DE LA DILIGENCE", 32, Color(0.95, 0.8, 0.35)))
	box.add_child(_title("Monte ton équipe — embauche jusqu'à %d hors-la-loi" % GameManager.CREW_SLOTS,
			17, Color(0.85, 0.82, 0.7)))
	_header = _title("", 17, Color(0.95, 0.9, 0.6))
	box.add_child(_header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 360)
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(_list)

	var go := Button.new()
	go.text = "🔫 LANCER L'ASSAUT"
	go.custom_minimum_size = Vector2(620, 60)
	go.add_theme_font_size_override("font_size", 22)
	go.pressed.connect(func() -> void: GameManager.start_coach_attack())
	box.add_child(go)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var disband := Button.new()
	disband.text = "Renvoyer l'équipe (remboursé)"
	disband.custom_minimum_size = Vector2(305, 46)
	disband.pressed.connect(func() -> void:
		GameManager.disband_crew()
		_refresh())
	row.add_child(disband)
	var back := Button.new()
	back.text = "← Carte"
	back.custom_minimum_size = Vector2(305, 46)
	back.pressed.connect(func() -> void: GameManager.goto_world_map())
	row.add_child(back)

	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_header.text = "Magot : %d $   ·   Équipe : %d / %d" % [
		SaveManager.total_money, GameManager.crew.size(), GameManager.CREW_SLOTS]
	for i in range(GameManager.crew_pool.size()):
		_list.add_child(_recruit_row(i))


func _recruit_row(idx: int) -> Control:
	var r: Dictionary = GameManager.crew_pool[idx]
	var hired := GameManager.crew_has(idx)
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.26, 0.30, 0.22, 0.9) if hired else Color(0.24, 0.18, 0.12, 0.9)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.5, 0.85, 0.45) if hired else Color(0.6, 0.45, 0.25)
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	info.add_child(_lbl("%s  «%s»" % [_role_icon(r["role"]), str(r["name"])], 20, Color(1, 1, 1)))
	info.add_child(_lbl("%s — %s" % [str(r["label"]), str(r["desc"])], 14, Color(0.82, 0.8, 0.7)))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 56)
	if hired:
		btn.text = "✓ Engagé"
		btn.disabled = true
	else:
		btn.text = "Engager\n%d $" % int(r["cost"])
		btn.disabled = not GameManager.can_hire(idx)
		btn.pressed.connect(func() -> void:
			if GameManager.hire(idx):
				AudioManager.play("pickup")
				_refresh())
	h.add_child(btn)
	return row


func _role_icon(role: String) -> String:
	match role:
		"gunman": return "🔫"
		"marksman": return "🎯"
		"medic": return "➕"
		"scout": return "🔭"
		"demolisher": return "🧨"
		_: return "🤠"


func _title(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _lbl(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
