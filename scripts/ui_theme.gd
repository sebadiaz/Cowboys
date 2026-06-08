extends RefCounted
class_name UiTheme
## ui_theme.gd
## Langage visuel partagé des menus "Dust & Dollars" : boutons cuir/laiton,
## panneau central lisible, titres western, et décor de fond peint (ui_backdrop).
## Un seul Theme appliqué à la racine -> tous les boutons/labels héritent du style.

const BackdropScript := preload("res://scripts/ui_backdrop.gd")

const GOLD := Color(0.95, 0.78, 0.32)
const CREAM := Color(0.98, 0.92, 0.72)
const LEATHER := Color(0.22, 0.14, 0.08)


## Theme global à poser sur la racine d'un écran (Control.theme = UiTheme.build()).
static func build() -> Theme:
	var t := Theme.new()
	t.set_stylebox("normal", "Button", _sb(Color(0.24, 0.15, 0.09), GOLD.darkened(0.1), 2.0))
	t.set_stylebox("hover", "Button", _sb(Color(0.34, 0.21, 0.11), Color(1.0, 0.85, 0.4), 2.0))
	t.set_stylebox("pressed", "Button", _sb(Color(0.16, 0.10, 0.05), GOLD.darkened(0.25), 2.0))
	t.set_stylebox("disabled", "Button", _sb(Color(0.18, 0.15, 0.12), Color(0.4, 0.35, 0.3), 2.0))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color(1, 0.98, 0.85))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.7, 0.65, 0.55))
	t.set_color("font_outline_color", "Button", Color(0.05, 0.03, 0.02))
	t.set_constant("outline_size", "Button", 4)
	t.set_font_size("font_size", "Button", 20)
	# Labels : crème lisible + contour, par défaut.
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", Color(0.05, 0.03, 0.02))
	t.set_constant("outline_size", "Label", 4)
	return t


## Décor de fond plein écran (à ajouter en premier enfant).
static func add_backdrop(parent: Control, mood := "menu") -> Control:
	var bd := Control.new()
	bd.set_script(BackdropScript)
	bd.set("mood", mood)
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bd)
	return bd


## Panneau central cuir (lisibilité du contenu par-dessus le décor).
## On y ajoute directement la VBox de contenu ; le padding vient du stylebox.
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.08, 0.05, 0.88)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = GOLD.darkened(0.05)
	sb.set_content_margin_all(30)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	p.add_theme_stylebox_override("panel", sb)
	return p


## Titre western (gros, doré, contour).
static func title(text: String, font_size: int, color := GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _sb(bg: Color, border: Color, bw: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(int(bw))
	sb.border_color = border
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb
