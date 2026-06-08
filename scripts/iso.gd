extends RefCounted
class_name Iso
## Projection de la vue (rendu seulement). La logique/physique reste en
## coordonnées cartésiennes "top-down" ; on ne transforme qu'à l'affichage.
##
## Deux modes :
##  • ISO 2:1 (par défaut) : losanges, `yaw` permet de pivoter la vue.
##  • TOP-DOWN (`top_down = true`) : projection IDENTITÉ (vue de dessus, sprites).
##    Tout le reste (visée souris, déplacement, effets, balles, cônes) marche tel
##    quel car il passe par project/unproject/depth/screen_to_world.

const S := 0.52        # échelle horizontale (iso)
const H := 0.5         # aplatissement vertical (2:1)
const WALL_HEIGHT := 34.0
const ACTOR_LIFT := 1.4

static var yaw := 0.0          # rotation de la vue iso (radians)
static var top_down := false   # true = vue de dessus (identité), pour le rendu sprites


## Monde -> écran (relatif).
static func project(p: Vector2) -> Vector2:
	if top_down:
		return p
	var r := p.rotated(yaw)
	return Vector2((r.x - r.y) * S, (r.x + r.y) * S * H)


## Inverse de project().
static func unproject(s: Vector2) -> Vector2:
	if top_down:
		return s
	var a := s.x / S
	var b := s.y / (S * H)
	return Vector2((a + b) * 0.5, (b - a) * 0.5).rotated(-yaw)


## Profondeur de tri (plus grand = devant).
static func depth(p: Vector2) -> float:
	if top_down:
		return p.y
	var r := p.rotated(yaw)
	return r.x + r.y


## Entrée écran (droite=+x, bas=+y) -> direction monde (contrôles alignés écran).
static func screen_to_world(v: Vector2) -> Vector2:
	if top_down:
		return v
	return (v.x * Vector2(1.0, -1.0) + v.y * Vector2(1.0, 1.0)).rotated(-yaw)
