extends Control
## main_menu.gd
## Menu principal : titre, bouton Jouer, rappel des contrôles et magot total.
## Layout via conteneurs (robuste sur desktop et mobile, quelle que soit la taille).

var _assist_btn: Button
var _magot_label: Label


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
	play.text = "🗺 JOUER — CARTE DU MONDE"
	play.custom_minimum_size = Vector2(460, 60)
	play.pressed.connect(_on_play)
	box.add_child(play)

	var levels := Button.new()
	levels.text = "⚡ NIVEAU RAPIDE"
	levels.custom_minimum_size = Vector2(460, 50)
	levels.pressed.connect(func(): GameManager.goto_level_select())
	box.add_child(levels)

	var shop := Button.new()
	shop.text = "🛒 BOUTIQUE (upgrades)"
	shop.custom_minimum_size = Vector2(460, 50)
	shop.pressed.connect(_on_shop)
	box.add_child(shop)

	var settings := Button.new()
	settings.text = "⚙ RÉGLAGES"
	settings.custom_minimum_size = Vector2(460, 46)
	settings.pressed.connect(func() -> void: GameManager.goto_settings())
	box.add_child(settings)

	# Mode assist (prototype facile) : basculable.
	_assist_btn = Button.new()
	_assist_btn.custom_minimum_size = Vector2(460, 46)
	_assist_btn.pressed.connect(_on_toggle_assist)
	box.add_child(_assist_btn)
	_refresh_assist()

	box.add_child(_spacer(10))

	box.add_child(_label(
		"Clavier : WASD/ZQSD bouger · Espace/clic TIRER · E interagir/porte · R recharger · Échap pause", 15,
		Color(0.3, 0.2, 0.12)))
	box.add_child(_label(
		"Mobile : joystick (gauche) + boutons TIR / RECH / E (droite)", 16,
		Color(0.3, 0.2, 0.12)))

	box.add_child(_spacer(12))

	_magot_label = _label(
		"Magot total : %d $   ·   Missions réussies : %d" % [
			SaveManager.total_money, SaveManager.missions_completed], 18,
		Color(0.3, 0.2, 0.12))
	box.add_child(_magot_label)

	# Réinitialiser la sauvegarde (discret) si la save bloque le test.
	var reset := Button.new()
	reset.text = "Réinitialiser la sauvegarde"
	reset.custom_minimum_size = Vector2(460, 36)
	reset.modulate = Color(1, 1, 1, 0.6)
	reset.pressed.connect(_on_reset_save)
	box.add_child(reset)
	AudioManager.play_music("theme")


func _on_play() -> void:
	GameManager.start_town()


func _on_shop() -> void:
	GameManager.goto_shop()


func _on_toggle_assist() -> void:
	GameManager.assist = not GameManager.assist
	_refresh_assist()


func _refresh_assist() -> void:
	if _assist_btn:
		_assist_btn.text = "Mode assist : %s (facile)" % ("ACTIVÉ" if GameManager.assist else "désactivé")


func _on_reset_save() -> void:
	SaveManager.total_money = 0
	SaveManager.missions_completed = 0
	SaveManager.levels_unlocked = 1
	SaveManager.towns_unlocked = 1
	SaveManager.notoriety = 0
	SaveManager.gang = []
	SaveManager.upgrades = SaveManager._default_upgrades()
	# On garde les réglages de confort (audio / contrôles tactiles).
	SaveManager.save_game()
	if _magot_label:
		_magot_label.text = "Sauvegarde réinitialisée."


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
