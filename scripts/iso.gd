extends RefCounted
class_name Iso
## Projection isométrique 2:1 (rendu seulement).
## La logique/physique du jeu reste en coordonnées cartésiennes "top-down" ;
## on projette uniquement à l'affichage. Origine de projection = (0,0) ; le
## décalage de centrage est géré par la position du noeud IsoRenderer.
##
## `yaw` permet de FAIRE PIVOTER la vue (autour de l'axe vertical du monde) sans
## toucher à la simulation : on tourne les coordonnées monde AVANT la projection
## iso. À 0 on retrouve la vue iso classique. Les scènes qui ne veulent pas de
## rotation (mission, saloon) remettent `Iso.yaw = 0.0`.

const S := 0.52        # échelle horizontale
const H := 0.5         # aplatissement vertical (2:1)
const WALL_HEIGHT := 34.0
const ACTOR_LIFT := 1.4  # hauteur du corps au-dessus du sol (x rayon)

static var yaw := 0.0   # rotation de la vue (radians), appliquée avant la projection


## Monde cartésien -> position écran (relative).
static func project(p: Vector2) -> Vector2:
	var r := p.rotated(yaw)
	return Vector2((r.x - r.y) * S, (r.x + r.y) * S * H)


## Inverse de project() : position écran (relative) -> monde cartésien.
static func unproject(s: Vector2) -> Vector2:
	var a := s.x / S            # = r.x - r.y
	var b := s.y / (S * H)      # = r.x + r.y
	return Vector2((a + b) * 0.5, (b - a) * 0.5).rotated(-yaw)


## Profondeur de tri : plus c'est grand, plus c'est "devant" (dessiné en dernier).
static func depth(p: Vector2) -> float:
	var r := p.rotated(yaw)
	return r.x + r.y


## Vecteur d'entrée écran (droite=+x, bas=+y) -> direction de déplacement monde.
## Donne des contrôles alignés sur l'écran (WASD = haut/bas/gauche/droite visuels),
## quelle que soit la rotation courante de la vue.
static func screen_to_world(v: Vector2) -> Vector2:
	return (v.x * Vector2(1.0, -1.0) + v.y * Vector2(1.0, 1.0)).rotated(-yaw)
